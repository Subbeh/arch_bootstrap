# Arch Bootstrap

Archbootstrap is used to automate the customization of your Arch installation. This includes installing packages and running custom scripts to set up your environment.

![This is an image](bootstrap.gif)

## Usage

Simply run the following command on your newly instally Arch environment to start the bootstrapping process. Please do **not** run as root, and instead run it under your own user.

```
curl -L b00t.me | bash
```

The script by default points to the config file located at the address http://config.b00t.me but can be changed to any local or remote file.

## Config

The config file is split up in sections which is represented in the GUI dialogs of the script as seen in the above capture, followed by any custom commands that are called from the menu entries.

A section starts with `=Secion_name` and contain menu entries formatted in a comma separated line as 

```
tag, package name(s), custom command name, description`
```

For example:

```
=Utilities
P,openssh,enable-sshd

=Desktop Environment
P,bspwm sxhkd,,bspwm window manager
A,polybar

=CMD enable-sshd: sudo systemctl enable sshd
```

### Syntax
The syntax for menu entries are as follows:

```
1. Tag
- P: packages are from official repository
- A: packages are from user repository (AUR)
2. Name
- Package name(s) to install, separated by a space
3. Command name
- Command to run as specified by the `=CMD:` section
4. Description
- If description is specified, this will replace the default package name in the menu entry
```

Depending on the construction of the meny entry line, only the tag is manditory. Either package name or description needs to specified, and the description is fully optional.

Please refer to the config file in this repository for more examples
