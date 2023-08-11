# Extract Release Files Script

## What is this?
This script extracts 6 correctly named release zip files for this repository from the official DR release zip files.

This is only used by the maintainer of the repository (who needs to have access to Standard & Pro version of the Engine)
every time a new DragonRuby version is released.


## Installation
It requires a local CRuby installation including `bundler` needs to installed once by running

```sh
bundle install --standalone
```

inside the `scripts/extract_release_files` directory.

## How to use
Download all 6 zip files (Windows, MacOS & Linux, Standard and Pro respectively) with their default names into the
same folder:

For example like this:
```
/home/bob/Downloads/
  dragonruby-gtk-windows-amd64.zip
  dragonruby-gtk-macos.zip
  dragonruby-gtk-linux-amd64.zip
  dragonruby-pro-windows-amd64.zip
  dragonruby-pro-macos.zip
  dragonruby-pro-linux-amd64.zip
```

and then run

```sh
./extract_release_files.rb /home/bob/Downloads/
```
