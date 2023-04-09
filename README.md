# Dragonruby for CI
This repository contains releases of publicly available parts of the [DragonRuby Game Toolkit](https://dragonruby.org/).

It is inofficial, maintained and extracted from the official zip files by me personally.

## Release contents
Each release contains zip files with filenames according to following pattern:

`dragonruby-for-ci-<VERSION>-<LICENSE_TIER>-<PLATFORM>.zip`

- `VERSION`: The DragonRuby version, for example `4.7`
- `LICENSE_TIER`: One of:
  - `standard`, which contains:
    - The DragonRuby executable (standard version)
    - `font.ttf` which is needed for DragonRuby to run
  - `pro`, which contains:
    - The DragonRuby executable (pro version)
    - `font.ttf` which is needed for DragonRuby to run
    - The `include` directory with C Headers needed for building C Extensions
- `PLATFORM`: One of:
  - `windows-amd64`
  - `macos`
  - `linux-amd64`

## Download via `curl`
To download the zip file you can for example execute following commands:

```sh
export DR_VERSION=4.7
export DR_LICENSE_TIER=pro
export DR_PLATFORM=windows-amd64

curl -L -O https://github.com/kfischer-okarin/dragonruby-for-ci/releases/download/$DR_VERSION/dragonruby-for-ci-$DR_VERSION-$DR_LICENSE_TIER-$DR_PLATFORM.zip
```
