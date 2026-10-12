// rgkeyd - global hotkeys for the Anbernic RG DS Plus (stock Buildroot OS).
//
// The stock OS handles the volume, power and back keys inside its launcher app
// (dmenu.bin). That app exits when it hands over to another app, so nothing
// listens to those keys while any other app is foregrounded. evdev delivers key
// events to every process that has the device open, so this daemon opens all
// input devices and performs the stock actions itself. It stays out of the way
// while the launcher menu is up, because the launcher handles the keys on its
// own (see rgkey-action.sh).
//
// Keys:
//   KEY_VOLUMEUP / KEY_VOLUMEDOWN / KEY_MUTE   volume / mute (PulseAudio)
//   KEY_POWER                                  suspend (stock pwr_new.sh)
//   KEY_BACK held down                         close the foreground app
//
// The power key doubles as the wake-up key, so after a suspend the daemon
// ignores power presses for a moment; otherwise the wake press would put the
// device straight back to sleep.

#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <glob.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include <linux/input.h>

#define ACTION_PATH "/opt/hishell/rgkey-action.sh"

// How long KEY_BACK must be held before it closes the app.
#define BACK_HOLD_MS 700
// How long to ignore the power key after a suspend, so the wake press does not
// immediately suspend again.
#define POWER_COOLDOWN_MS 3000

// Lid (hall) sensor: /sys/class/anbernic_misc/hallkey reads 3 when the lid is
// open and 2 when it is closed (bit 0 is set while open). The hall IRQ is an
// enabled wakeup source, so opening the lid resumes the SoC on its own.
#define HALL_PATH "/sys/class/anbernic_misc/hallkey"
#define HALL_POLL_MS 500
#define LID_COOLDOWN_MS 2000

#define MAX_DEVS 64

static int fds[MAX_DEVS];
static int nfds;

static long now_ms(void) {
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (long)ts.tv_sec * 1000L + (long)ts.tv_nsec / 1000000L;
}

static void logmsg(const char *fmt, ...) {
	char buf[256];
	va_list ap;

	va_start(ap, fmt);
	vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);

	syslog(LOG_INFO, "%s", buf);
	fprintf(stderr, "rgkeyd: %s\n", buf);
	fflush(stderr);
}

// Runs one action in the helper script and waits for it. Waiting matters for
// "power": pwr_new.sh blocks in the kernel until the device resumes, which is
// how the daemon knows when to start the wake cooldown.
static void run_action(const char *action) {
	pid_t pid = fork();

	if (pid == 0) {
		execl(ACTION_PATH, ACTION_PATH, action, (char *)NULL);
		_exit(127);
	}
	if (pid < 0) {
		logmsg("fork failed: %s", strerror(errno));
		return;
	}

	int status = 0;
	while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
	}
	logmsg("%s", action);
}

static int open_devices(void) {
	glob_t g;
	nfds = 0;

	if (glob("/dev/input/event*", 0, NULL, &g) != 0) {
		globfree(&g);
		return 0;
	}
	for (size_t i = 0; i < g.gl_pathc && nfds < MAX_DEVS; i++) {
		int fd = open(g.gl_pathv[i], O_RDONLY | O_NONBLOCK);
		if (fd >= 0)
			fds[nfds++] = fd;
	}
	globfree(&g);
	return nfds;
}

static void drain_all(void) {
	struct input_event ev;

	for (int i = 0; i < nfds; i++) {
		if (fds[i] < 0)
			continue;
		while (read(fds[i], &ev, sizeof(ev)) == (ssize_t)sizeof(ev)) {
		}
	}
}

static int read_hall(void) {
	char buf[16];
	int fd = open(HALL_PATH, O_RDONLY);

	if (fd < 0)
		return -1;
	ssize_t n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	if (n <= 0)
		return -1;
	buf[n] = '\0';
	return atoi(buf);
}

// Suspends while the lid is closed. The state is tracked so a scan only acts on
// the open -> closed edge; opening the lid wakes the device through the hall
// IRQ, so nothing is needed on the way back up.
static void handle_hall(void) {
	static int hall_closed;
	static long lid_cooldown_until;

	int v = read_hall();
	if (v < 0)
		return;

	int closed = (v & 1) == 0;
	long now = now_ms();

	if (!closed) {
		hall_closed = 0;
		return;
	}
	if (hall_closed || now < lid_cooldown_until)
		return;

	hall_closed = 1;
	run_action("lid-close");
	lid_cooldown_until = now_ms() + LID_COOLDOWN_MS;

	// After a suspend this returns already resumed; refresh so a stale closed
	// reading cannot suspend a second time.
	v = read_hall();
	if (v >= 0)
		hall_closed = (v & 1) == 0;
}

int main(void) {
	openlog("rgkeyd", LOG_PID, LOG_DAEMON);

	if (open_devices() == 0) {
		logmsg("no input devices found");
		return 1;
	}
	logmsg("started, %d device(s)", nfds);

	int back_down = 0;
	int back_fired = 0;
	long back_press = 0;
	long power_cooldown_until = 0;
	long last_hall = 0;

	for (;;) {
		long now = now_ms();

		// Poll the lid sensor; the poll timeout below bounds the interval.
		if (now - last_hall >= HALL_POLL_MS) {
			last_hall = now;
			handle_hall();
		}

		struct pollfd pfd[MAX_DEVS];
		for (int i = 0; i < nfds; i++) {
			pfd[i].fd = fds[i];
			pfd[i].events = POLLIN;
		}

		// Wake up for the next lid poll, or when a held back button reaches
		// its threshold.
		int timeout = (int)(HALL_POLL_MS - (now_ms() - last_hall));
		if (timeout < 0)
			timeout = 0;
		if (back_down && !back_fired) {
			long left = BACK_HOLD_MS - (now_ms() - back_press);
			if (left < timeout)
				timeout = left > 0 ? (int)left : 0;
		}

		int ready = poll(pfd, nfds, timeout);
		if (ready < 0) {
			if (errno == EINTR)
				continue;
			logmsg("poll failed: %s", strerror(errno));
			break;
		}

		if (ready == 0) {
			if (back_down && !back_fired && now_ms() - back_press >= BACK_HOLD_MS) {
				back_fired = 1;
				run_action("back-close");
			}
			continue;
		}

		for (int i = 0; i < nfds; i++) {
			if (fds[i] < 0)
				continue;
			if (pfd[i].revents & (POLLERR | POLLHUP | POLLNVAL)) {
				// Device went away (controller unplugged, etc.).
				close(fds[i]);
				fds[i] = -1;
				continue;
			}
			if (!(pfd[i].revents & POLLIN))
				continue;

			struct input_event ev;
			while (read(fds[i], &ev, sizeof(ev)) == (ssize_t)sizeof(ev)) {
				if (ev.type != EV_KEY)
					continue;

				if (ev.code == KEY_VOLUMEUP) {
					if (ev.value == 1)
						run_action("vol-up");
				} else if (ev.code == KEY_VOLUMEDOWN) {
					if (ev.value == 1)
						run_action("vol-down");
				} else if (ev.code == KEY_MUTE) {
					if (ev.value == 1)
						run_action("mute");
				} else if (ev.code == KEY_POWER) {
					if (ev.value == 1 && now_ms() >= power_cooldown_until) {
						run_action("power");
						power_cooldown_until = now_ms() + POWER_COOLDOWN_MS;
						drain_all();
					}
				} else if (ev.code == KEY_BACK) {
					if (ev.value == 1) {
						back_down = 1;
						back_fired = 0;
						back_press = now_ms();
					} else if (ev.value == 0) {
						back_down = 0;
						back_fired = 0;
					}
				}
			}
		}
	}

	return 0;
}
