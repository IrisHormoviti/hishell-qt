# Hishell File Manager
This is a unique file manager for Linux that focuses on per folder customization. 
Still very much a work in progress
## What is "Hishell"
Hishell isn't intended to just be the name for this file manager, but a specific spec for formatting folders to appear a certain way between systems. This includes:
- [X] Folder icons
- [ ] Dynamic icons
- [X] Folder titles (Separate from names)
- [X] Wallpapers
- [ ] Custom themes
- [ ] Playing audio when entering a folder
- [X] Window control overrides
- [ ] Custom item positions
- [X] Multiple folder views within one directory
- [X] View modes (Grid, List etc)
- [ ] Sorting modes
- [X] Layout directions
- [ ] "Stash" feature (Hidden items)
- [ ] Behavior overrides (e.g. always open in new windows)
- [ ] In-folder text or images
- [ ] Directory inheritance
- [X] Descriptor generators (titles and icons read from file contents)
- [ ] Potentially scripting...? (Security is a big concern there)

All these things would be able to be set per folder using a few dot files, allowing the user to customize their workspace, aesthetically and practically, and even create mini applications to help with their workflow.

## About hishell-qt
This is meant to be a reference implementation for this Hishell spec, which I might also use in other projects. This app is strictly a file manager, made in QT and Kirigami, with the backend written in Rust.
Planned features:
- [ ] Everything in the hishell spec
- [X] Copy, Paste etc, essential file manager stuff
- [X] Selection mode, enabled by clicking and holding on an item or pressing space.
- [X] Breadcrumb path bar
- [ ] File thumbnailing
- [ ] Quickly filtering files by typing
- [X] Menubar with context related actions
- [X] Right click context menu
- [X] "Open as" dialog

## Descriptors and generators

A descriptor is a desktop entry that names another path and gives it a title,
comment and icon, without writing anything beside that path:

```ini
[Desktop Entry]
Type=Directory
Path=/mnt/sdcard
Name=SD Card
Icon=media-flash-sd-mmc
```

`Type=File` does the same for a single file. Descriptors are read from
`hishell/directories` under the XDG data directories and from
`/run/clam-removable/directories`; the generated-descriptor cache is a root too.

A **descriptor generator** is discovered the way a thumbnailer is:

```ini
[Descriptor Generator Entry]
TryExec=clam-nds-descriptor
Exec=clam-nds-descriptor %i %o
Icon=application-x-nintendo-ds-rom
MimeType=application/vnd.nintendo.nitro.rom;
```

It runs for files of a matching content type, writes a descriptor, and Hishell
caches it under `$XDG_CACHE_HOME/hishell/descriptors`. A DS ROM therefore shows
its banner title and its own cartridge artwork instead of a generic MIME icon.
The optional `Icon` is the themed placeholder used before generation finishes
and after a generator fails, so such a file still looks like the type it is. A
type an installed generator handles is not also sent to a thumbnailer, so the
two pictures cannot fight over the item. Generators are deliberately
format-agnostic: the shell only knows the directories, the MIME match and the
`%i`/`%o` contract.

## Unusual design choices
### No double clicking
In this file manager, double-clicking isn't and will not be a thing. I personally think this is a weird design choice that's just been left around since early computers, and is only expected in file managers, which is inconsistent with any other app on a desktop. The interface will be designed around this, selection will still be easy.
### No sidebar / favorites (Well you can still have it)
There will not be a sidebar. This app is designed for opening folders, and not as the app you open to open folders.
What? What's the diffrence?
You shouldn't have to open the file manager directly in order to navigate to a folder, and it should just open when you open a folder
Most desktop environments have some sort of standard way to have shortcuts to your folders, be it desktop icons or a "Places" menu. That should be used instead for quickly opening folders.
If you still want a sidebar though, you'll want to add a specific folder to the left of your screen within the default config, and set it to list view.
### Settings?
The settings will be the "general config", a folder config that can will be applied to every folder by default, stored in `~/.config/hishell/folder.cfg`, with a system-wide layer at `$XDG_CONFIG_DIRS/hishell/folder.cfg` (default `/etc/xdg/hishell/folder.cfg`) underneath it for device defaults. Everything there can be altered on a per folder basis. There will be a GUI for everything in here, just don't expect a "Settings" menu.

## Install / Build

### Build

```bash
cargo build
```

Qt 6 and KF6 are discovered from the system by default. If a machine keeps
them somewhere else (a private prefix, Homebrew, a cross sysroot), point
`QT_INCLUDE_PATH`, `QT_LIBRARY_PATH`, `KF6_INCLUDE_PATH`, `QMAKE` and `MOC` at
it in `~/.cargo/config.toml` rather than in the repo's `.cargo/config.toml`.

### Run

```bash
cargo run
```

Or add a path:

```bash
cargo run -- ~/Downloads
```
