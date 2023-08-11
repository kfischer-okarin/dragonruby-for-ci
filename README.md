# Dragonruby for CI
This repository contains releases of publicly available parts of the [DragonRuby Game Toolkit](https://dragonruby.org/).

It can be used for running automated tests or builds on your CI server.

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

## Running DragonRuby tests on CI (without a display)

```sh
# This assumes your game is in the `mygame` directory and contains a file `mygame/tests.rb`
# containing your tests. It will save the test output in logs/tests.log
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ./dragonruby mygame --test tests.rb | tee tests.log
# This grep call is a workaround to make CI jobs fail properly since DragonRuby does not return an
# error exit code when the tests fail
grep '\[Game\] 0 test(s) failed.' tests.log
```

## Example Github Actions Configuration

Put following file into the folder `.github/workflows/` in your repository
(filename can be anything you like as long it has the `yml` extension).

```yml
name: Test

on:
  push:

jobs:
  test:
    strategy:
      matrix: # This matrix will run 18 jobs (3 versions x 2 tiers x 3 platforms)
        # Remove the configurations you don't need
        dr_version:
          - '4.7'
          - '5.0'
          - '5.4'
        dr_license_tier:
          - standard
          - pro
        runner:
          - windows-2022
          - macos-12
          - ubuntu-22.04
        include:
          - runner: windows-2022
            dr_platform: windows-amd64
          - runner: macos-12
            dr_platform: macos
          - runner: ubuntu-22.04
            dr_platform: linux-amd64
      fail-fast: false
    runs-on: ${{ matrix.runner }}
    defaults:
      run:
        shell: bash
    steps:
      - uses: actions/checkout@v3
      - name: Download dragonruby
        run: |
          curl -L -o dragonruby.zip https://github.com/kfischer-okarin/dragonruby-for-ci/releases/download/${{ matrix.dr_version }}/dragonruby-for-ci-${{ matrix.dr_version }}-${{ matrix.dr_license_tier }}-${{ matrix.dr_platform }}.zip
          unzip dragonruby.zip
          chmod u+x ./dragonruby
      - name: Run tests
        env:
          SDL_VIDEODRIVER: dummy
          SDL_AUDIODRIVER: dummy
        run: |
          # See "Running DragonRuby tests on CI (without a display)" in README.md for further explanations
          ./dragonruby mygame --test tests.rb | tee tests.log
          grep '\[Game\] 0 test(s) failed.' tests.log
```
