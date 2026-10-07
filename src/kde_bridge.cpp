#include <KApplicationTrader>
#include <KIO/ApplicationLauncherJob>
#include <KIO/CopyJob>
#include <KIO/Job>
#include <KService>
#include <QCoreApplication>
#include <QEventLoop>
#include <QFileInfo>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusUnixFileDescriptor>
#include <QDebug>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeyEvent>
#include <QMimeDatabase>
#include <QMimeType>
#include <QRandomGenerator>
#include <QUrl>
#include <QVariantMap>
#include <QWindow>
#include <fcntl.h>
#include <unistd.h>

static thread_local QByteArray g_result;

namespace {

constexpr int PortalIdle = 0;
constexpr int PortalPending = 1;
constexpr int PortalFailed = 2;

constexpr char PortalService[] = "org.freedesktop.portal.Desktop";
constexpr char PortalObjectPath[] = "/org/freedesktop/portal/desktop";

int g_portalState = PortalIdle;
QString g_portalRequestPath;

QString portalRequestPath(const QString &token)
{
	QString sender = QDBusConnection::sessionBus().baseService();
	if (sender.startsWith(QLatin1Char(':'))) {
		sender.remove(0, 1);
	}
	sender.replace(QLatin1Char('.'), QLatin1Char('_'));
	return QStringLiteral("/org/freedesktop/portal/desktop/request/%1/%2").arg(sender, token);
}
}

class HishellPortalRequestListener : public QObject
{
	Q_OBJECT
public:
	using QObject::QObject;

public slots:
	void onResponse(uint response, const QVariantMap &results)
	{
		Q_UNUSED(results)
		g_portalState = response == 2 ? PortalFailed : PortalIdle;
	}
};

static HishellPortalRequestListener *portalListener()
{
	static auto *listener = new HishellPortalRequestListener(QCoreApplication::instance());
	return listener;
}

extern "C" void hishell_menu_key_pressed(void);

// The context menu key would otherwise pop a menu up at the cursor; hand it to
// the application instead so it follows the focused item like the gamepad's
// menu button does.
//
// The filter also swallows the bare-Alt shortcut override: QQuickMenuBar uses it
// to enter its Alt mode, which grabs focus and closes whatever menu is open.
// Kirigami shows the mnemonic underlines from Alt key presses, so keeping that
// event away from the menu bar leaves the underlines working while Alt no longer
// dismisses an open menu.
class HishellMenuKeyFilter : public QObject
{
public:
	using QObject::QObject;

protected:
	bool eventFilter(QObject *receiver, QEvent *event) override
	{
		if (event->type() == QEvent::KeyPress) {
			auto *keyEvent = static_cast<QKeyEvent *>(event);
			if (keyEvent->key() == Qt::Key_Menu && !keyEvent->isAutoRepeat()) {
				hishell_menu_key_pressed();
				return true;
			}
		} else if (event->type() == QEvent::ShortcutOverride) {
			auto *keyEvent = static_cast<QKeyEvent *>(event);
			if ((keyEvent->key() == Qt::Key_Alt || keyEvent->key() == Qt::Key_Meta)
			    && keyEvent->modifiers() == Qt::AltModifier) {
				return true;
			}
		}
		return QObject::eventFilter(receiver, event);
	}
};

extern "C" {

const char *hishell_open_with_apps(const char *path)
{
	const QMimeDatabase db;
	const QMimeType mime = db.mimeTypeForFile(QString::fromUtf8(path));
	const QString mimeName = mime.name();
	const KService::Ptr preferred = KApplicationTrader::preferredService(mimeName);

	QJsonArray apps;
	const KService::List services = KApplicationTrader::queryByMimeType(mimeName);
	for (const KService::Ptr &service : services) {
		QJsonObject app;
		app["id"] = service->storageId();
		app["name"] = service->name();
		app["icon"] = service->icon();
		app["comment"] = service->comment();
		app["noDisplay"] = service->noDisplay();
		app["isDefault"] = preferred && preferred->storageId() == service->storageId();
		apps.append(app);
	}

	QJsonObject root;
	root["mime"] = mimeName;
	root["mimeDescription"] = mime.comment();
	root["apps"] = apps;
	g_result = QJsonDocument(root).toJson(QJsonDocument::Compact);
	return g_result.constData();
}

static bool launchService(const KService::Ptr &service, const QString &path)
{
	if (!service) {
		return false;
	}
	auto *job = new KIO::ApplicationLauncherJob(service);
	job->setUrls({QUrl::fromLocalFile(path)});
	QObject::connect(job, &KJob::finished, job, [](KJob *finishedJob) {
		if (finishedJob->error() != KJob::NoError) {
			qWarning() << "hishell: failed to launch application:" << finishedJob->errorString();
		}
	});
	job->start();
	return true;
}

bool hishell_open_with_launch(const char *storageId, const char *path)
{
	return launchService(KService::serviceByStorageId(QString::fromUtf8(storageId)), QString::fromUtf8(path));
}

bool hishell_open_with_default(const char *path)
{
	const QMimeDatabase db;
	const QMimeType mime = db.mimeTypeForFile(QString::fromUtf8(path));
	return launchService(KApplicationTrader::preferredService(mime.name()), QString::fromUtf8(path));
}

const char *hishell_default_app(const char *path)
{
	QJsonObject app;
	const QString filePath = QString::fromUtf8(path);
	if (!filePath.isEmpty()) {
		const QMimeDatabase db;
		const QMimeType mime = db.mimeTypeForFile(filePath);
		const KService::Ptr service = KApplicationTrader::preferredService(mime.name());
		if (service) {
			app["id"] = service->storageId();
			app["name"] = service->name();
			app["icon"] = service->icon();
		}
	}
	g_result = QJsonDocument(app).toJson(QJsonDocument::Compact);
	return g_result.constData();
}

// Rename (move) a local file to newName within the same directory using KIO,
// so the operation goes through the same error reporting as other KDE apps.
// Returns an empty string on success, otherwise the job's error message.
const char *hishell_rename(const char *path, const char *newName)
{
	const QString filePath = QString::fromUtf8(path);
	const QString name = QString::fromUtf8(newName);
	if (filePath.isEmpty() || name.isEmpty()) {
		g_result = QStringLiteral("Invalid path or name.").toUtf8();
		return g_result.constData();
	}

	const QUrl src = QUrl::fromLocalFile(filePath);
	QUrl dest = src.adjusted(QUrl::RemoveFilename);
	dest.setPath(QUrl::fromLocalFile(QFileInfo(filePath).absolutePath() + QLatin1Char('/') + name).path());

	KIO::CopyJob *job = KIO::move(src, dest, KIO::HideProgressInfo);
	QEventLoop loop;
	QObject::connect(job, &KJob::finished, &loop, &QEventLoop::quit);
	job->start();
	loop.exec();

	g_result = job->error() == KJob::NoError ? QByteArray() : job->errorString().toUtf8();
	return g_result.constData();
}
}

extern "C" {

bool hishell_portal_open_with(const char *path)
{
	QDBusConnection bus = QDBusConnection::sessionBus();
	if (!bus.isConnected() || !(bus.connectionCapabilities() & QDBusConnection::UnixFileDescriptorPassing)) {
		return false;
	}

	const int fd = ::open(path, O_RDONLY | O_CLOEXEC);
	if (fd < 0) {
		return false;
	}
	const QDBusUnixFileDescriptor descriptor(fd);
	::close(fd);
	if (!descriptor.isValid()) {
		return false;
	}

	auto *listener = portalListener();
	if (!g_portalRequestPath.isEmpty()) {
		bus.disconnect(QString::fromLatin1(PortalService), g_portalRequestPath,
		               QStringLiteral("org.freedesktop.portal.Request"), QStringLiteral("Response"),
		               listener, SLOT(onResponse(uint,QVariantMap)));
		g_portalRequestPath.clear();
	}

	const QString token = QStringLiteral("hishell%1").arg(QRandomGenerator::global()->generate64(), 16, 16, QLatin1Char('0'));
	const QString requestPath = portalRequestPath(token);
	if (!bus.connect(QString::fromLatin1(PortalService), requestPath,
	                 QStringLiteral("org.freedesktop.portal.Request"), QStringLiteral("Response"),
	                 listener, SLOT(onResponse(uint,QVariantMap)))) {
		return false;
	}
	g_portalRequestPath = requestPath;
	g_portalState = PortalPending;

	QDBusMessage message = QDBusMessage::createMethodCall(
		QString::fromLatin1(PortalService),
		QString::fromLatin1(PortalObjectPath),
		QStringLiteral("org.freedesktop.portal.OpenURI"),
		QStringLiteral("OpenFile"));
	message << QString()
	        << QVariant::fromValue(descriptor)
	        << QVariantMap{{QStringLiteral("ask"), true}, {QStringLiteral("handle_token"), token}};

	auto *watcher = new QDBusPendingCallWatcher(bus.asyncCall(message), listener);
	QObject::connect(watcher, &QDBusPendingCallWatcher::finished, watcher, [requestPath, listener](QDBusPendingCallWatcher *self) {
		const QDBusMessage reply = self->reply();
		if (requestPath == g_portalRequestPath) {
			if (reply.type() == QDBusMessage::ErrorMessage) {
				qWarning() << "hishell: portal OpenFile call failed:" << reply.errorMessage();
				g_portalState = PortalFailed;
			} else if (!reply.arguments().isEmpty()) {
				const QString handle = reply.arguments().constFirst().value<QDBusObjectPath>().path();
				if (!handle.isEmpty() && handle != requestPath) {
					QDBusConnection::sessionBus().connect(QString::fromLatin1(PortalService), handle,
					                                      QStringLiteral("org.freedesktop.portal.Request"), QStringLiteral("Response"),
					                                      listener, SLOT(onResponse(uint,QVariantMap)));
				}
			}
		}
		self->deleteLater();
	});

	return true;
}

int hishell_portal_poll(void)
{
	if (g_portalState == PortalFailed) {
		g_portalState = PortalIdle;
		return PortalFailed;
	}
	return g_portalState;
}

bool hishell_send_key(int key)
{
	QObject *target = QGuiApplication::focusWindow();
	if (!target) {
		target = QGuiApplication::focusObject();
	}
	if (!target) {
		return false;
	}

	QKeyEvent press(QEvent::KeyPress, key, Qt::NoModifier);
	QCoreApplication::sendEvent(target, &press);
	QKeyEvent release(QEvent::KeyRelease, key, Qt::NoModifier);
	QCoreApplication::sendEvent(target, &release);
	return true;
}

void hishell_hook_menu_key(void)
{
	static QObject *filter = nullptr;
	if (filter) {
		return;
	}
	QCoreApplication *application = QCoreApplication::instance();
	if (!application) {
		return;
	}
	filter = new HishellMenuKeyFilter(application);
	application->installEventFilter(filter);
}
}

#include "moc_kde_bridge.cpp"
