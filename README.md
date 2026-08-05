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
- [ ] Layout directions
- [ ] "Stash" feature (Hidden items)
- [ ] Behavior overrides (e.g. always open in new windows)
- [ ] In-folder text or images
- [ ] Directory inheritance
- [ ] Potentially scripting...? (Security is a big concern there)

All these things would be able to be set per folder using a few dot files, allowing the user to customize their workspace, aesthetically and practically, and even create mini applications to help with their workflow.

## About hishell-qt
This is meant to be a reference implementation for this Hishell spec, which I might also use in other projects. This app is strictly a file manager, made in QT and Kirigami, with the backend written in Rust.
Planned features:
- [ ] Everything in the hishell spec
- [ ] Copy, Paste etc, essential file manager stuff
- [ ] Selection mode, enabled by clicking and holding on an item or pressing space.
- [ ] Breadcrumb path bar
- [ ] Quickly filtering files by typing
- [ ] Menubar with context related actions
- [ ] Right click context menu
- [ ] "Open as" dialog

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
The settings will be the "general config", a folder config that can will be applied to every folder by default, stored in `~/.config/hishell/folder.cfg`. Everything there can be altered on a per folder basis. There will be a GUI for everything in here, just don't expect a "Settings" menu.

## Install / Build
Not ready yet
