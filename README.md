# omarchy-oncachy

[Omarchy](https://github.com/omacom/omarchy)'s desktop on [CachyOS](https://cachyos.org),
as regular pacman packages built from the official Omarchy sources.

CachyOS keeps its kernel, drivers, bootloader and system configuration. The packages ship
Omarchy's desktop runtime, configs, themes and applications, but not its system and boot stack
(Limine, Plymouth, mkinitcpio, PAM, sudoers, distribution identity).

Unofficial community project, not affiliated with Omarchy or CachyOS.

## Packages

| Package | Contents |
|---|---|
| `omarchy-oncachy` | Omarchy's `bin/`, `config/`, `default/`, `shell/`, `themes/`… under `/usr/share/omarchy`, the Omarchy session, and `omarchy-oncachy-setup` |
| `omarchy-oncachy-desktop` | Meta package: Omarchy's application list (`install/omarchy-base.packages`) minus Plymouth, kernel-modules-hook and tldr (tealdeer instead) |

Omarchy's own repository (`[omarchy]`, pkgs.omarchy.org) provides Hyprland, quickshell and its
desktop tools; it is added ahead of the CachyOS repositories.

## Install on an existing CachyOS

Start from a CachyOS install with Hyprland or without a desktop, on your normal user:

```bash
git clone https://github.com/Siguenos/omarchy-oncachy.git
cd omarchy-oncachy
./install.sh            # or --yes for no questions
```

`install.sh` takes a Snapper snapshot when available, adds the repositories, installs
`omarchy-oncachy-desktop`, then runs `omarchy-oncachy-setup`:

- as root: keyboard layout for Hyprland (`XKBLAYOUT` in `/etc/vconsole.conf`, from the X11
  layout), Omarchy as SDDM's default session, SDDM and NetworkManager enabled;
- as the user: backup of `~/.config` to `~/.local/state/omarchy-oncachy/`, Omarchy configs,
  matching fcitx5 keyboard profile, then Omarchy's `omarchy-provision-user`.

Reboot and log in to the Omarchy session. Updates come with `sudo pacman -Syu` (or `omarchy update`).

### Repository

`install.sh` sets this up; to do it by hand, import the signing key and add the repository
(here after `[options]`, ahead of the other repositories):

```bash
sudo pacman-key --add keys/omarchy-oncachy.asc
sudo pacman-key --lsign-key F5CC831F86EEDEF2988D958F9C2D1A8DCDB97DAB
```

```ini
[omarchy-oncachy]
SigLevel = Required
Server = https://github.com/Siguenos/omarchy-oncachy/releases/download/repo
```

Packages and database are signed by the subkey `02AA039EC307C7DA1C9AF018468F92E58933DC1F` of
`keys/omarchy-oncachy.asc`. The *Publish* workflow rebuilds, signs and uploads them to the
`repo` release whenever `pkgbuilds/` changes on `main`.

## Build

```bash
bin/build.sh --nodeps                 # packages in out/
./install.sh --packages out           # install them instead of the repository's
```

`pkgbuilds/omarchy-oncachy/patches/*.patch` are applied to the Omarchy sources in `prepare()`.

## Follow Omarchy releases

- `bin/bump-omarchy.sh [VERSION]` pins another Omarchy tag (latest stable by default): version,
  commit, checksum and the meta package's dependencies.
- `bin/upstream-report.sh OLD NEW` summarises what changed in the parts this project filters out
  or reimplements (package list, migrations, `etc/`, system scripts, user provisioning).

## Tests

```bash
bin/build.sh --nobuild
OMARCHY_TEST_SOURCE=.cache/build/omarchy-oncachy/src/omarchy python3 tests/test_package.py
```

## Credits

Based on [omarchy-on-cachyos](https://github.com/MiguelU-coder/omarchy-on-cachyos) by Mark Roboff,
MiguelU-coder and contributors (MIT). Omarchy is © its authors, MIT licensed.
