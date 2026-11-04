import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PKGBUILD = ROOT / 'pkgbuilds/omarchy-oncachy/PKGBUILD'
SETUP = ROOT / 'pkgbuilds/omarchy-oncachy/omarchy-oncachy-setup'
EXTRAS = ROOT / 'pkgbuilds/omarchy-oncachy/omarchy-oncachy-extras'
# Upstream checkout at the pinned commit, e.g. .cache/build/omarchy-oncachy/src/omarchy
# after `bin/build.sh --nobuild`.
SOURCE = os.environ.get('OMARCHY_TEST_SOURCE')


def run(*args, **kwargs):
    return subprocess.run(args, text=True, capture_output=True, **kwargs)


def pkgbuild_value(expression):
    result = run('bash', '-c', 'source "$1"; ' + expression, 'bash', str(PKGBUILD))
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


class ScriptTests(unittest.TestCase):
    def test_bash_syntax(self):
        for path in [*ROOT.glob('bin/*.sh'), *ROOT.glob('iso/*.sh'), *ROOT.glob('iso/calamares/omarchy-oncachy-*'),
                     ROOT / 'install.sh', PKGBUILD, SETUP, EXTRAS]:
            result = run('bash', '-n', str(path))
            self.assertEqual(result.returncode, 0, f'{path}: {result.stderr}')

    def test_version_matches_tag(self):
        tag = pkgbuild_value('echo "$_tag"')
        self.assertEqual(pkgbuild_value('echo "$pkgver"'), tag.removeprefix('v').replace('-', ''))
        self.assertRegex(pkgbuild_value('echo "$_commit"'), r'^[0-9a-f]{40}$')
        self.assertIn('#commit=$_commit', PKGBUILD.read_text())

    def test_update_kind(self):
        cases = {
            ('4.0.6', '4.0.7'): 'patch',
            ('v4.0.9', 'v4.0.10'): 'patch',
            ('4.0.6', '4.1.0'): 'minor',
            ('4.5.0-rc3', '4.5.0'): 'minor',
            ('4.0.6', '5.0.0'): 'major',
            ('4.0.6', '4.5.0-rc3'): 'prerelease',
            ('4.0.6', '4.0.5'): 'downgrade',
            ('4.5.0', '4.5.0-rc3'): 'downgrade',
        }
        for (old, new), kind in cases.items():
            result = run(str(ROOT / 'bin/update-kind.sh'), old, new)
            self.assertEqual(result.stdout.strip(), kind, f'{old} -> {new}: {result.stderr}')

    def test_extras_list(self):
        result = run('bash', '-c', 'source "$1"; list_packages "$2"', 'bash', str(EXTRAS),
                     str(ROOT / 'extras/extras.packages'))
        self.assertEqual(result.returncode, 0, result.stderr)
        packages = result.stdout.split()
        self.assertIn('jetbrains-toolbox', packages)
        self.assertEqual(len(packages), len(set(packages)))
        self.assertTrue(all(p and '#' not in p and ' ' not in p for p in packages))

    def test_desktop_depends_filter(self):
        with tempfile.TemporaryDirectory() as tmp:
            packages = Path(tmp) / 'omarchy-base.packages'
            packages.write_text('# comment\nhyprland\nplymouth  # boot splash\ntldr\nkernel-modules-hook\n\nwaybar\n')
            result = run('bash', str(ROOT / 'bin/desktop-depends.sh'), str(packages))
            self.assertEqual(result.returncode, 0, result.stderr)
            listed = result.stdout.split()
            self.assertIn('hyprland', listed)
            self.assertIn('tealdeer', listed)
            for excluded in ('plymouth', 'tldr', 'kernel-modules-hook', '#'):
                self.assertNotIn(excluded, listed)
            self.assertEqual(listed, sorted(set(listed)))  # byte order, as LC_ALL=C

    def test_pacman_config_adds_repository_first(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / 'pacman.conf'
            config.write_text('[options]\nIgnorePkg = custom\n\n[omarchy]\nServer = OLD\n\n'
                              '[cachyos]\nInclude = /etc/pacman.d/cachyos-mirrorlist\n\n[extra]\n')
            result = run('awk', '-v', 'name=omarchy', '-v', 'server=https://pkgs.omarchy.org/stable/$arch',
                         '-v', 'siglevel=Required DatabaseOptional',
                         '-f', str(ROOT / 'bin/pacman-config.awk'), str(config))
            self.assertEqual(result.returncode, 0, result.stderr)
            rendered = result.stdout
            self.assertEqual(rendered.count('[omarchy]'), 1)
            self.assertNotIn('Server = OLD', rendered)
            self.assertIn('IgnorePkg = custom', rendered)
            self.assertLess(rendered.index('[options]'), rendered.index('[omarchy]'))
            self.assertLess(rendered.index('[omarchy]'), rendered.index('[cachyos]'))


class SetupTests(unittest.TestCase):
    def setup_shell(self, tmp, script):
        env = {**os.environ,
               'OMARCHY_ONCACHY_VCONSOLE': str(Path(tmp) / 'vconsole.conf'),
               'OMARCHY_ONCACHY_X11_KEYBOARD': str(Path(tmp) / '00-keyboard.conf'),
               'OMARCHY_ONCACHY_SDDM_STATE': str(Path(tmp) / 'sddm/state.conf'),
               'OMARCHY_ONCACHY_SDDM_THEME_CONF': str(Path(tmp) / 'sddm.conf.d/10-omarchy-theme.conf'),
               'OMARCHY_ONCACHY_NO_SYSTEMCTL': '1'}
        return run('bash', '-c', 'source "$1"; ' + script, 'bash', str(SETUP), env=env)

    def keyboard(self, vconsole=None, x11=None):
        with tempfile.TemporaryDirectory() as tmp:
            if vconsole is not None:
                (Path(tmp) / 'vconsole.conf').write_text(vconsole)
            if x11 is not None:
                (Path(tmp) / '00-keyboard.conf').write_text(x11)
            result = self.setup_shell(tmp, 'keyboard_layout')
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout.split()

    def test_keyboard_sources(self):
        x11 = ('Section "InputClass"\n  Identifier "system-keyboard"\n'
               '  Option "XkbLayout" "fr"\n  Option "XkbVariant" "latin9"\nEndSection\n')
        self.assertEqual(self.keyboard(), ['us'])
        self.assertEqual(self.keyboard('XKBLAYOUT="de"\nXKBVARIANT=nodeadkeys\n', x11), ['de', 'nodeadkeys'])
        self.assertEqual(self.keyboard('KEYMAP=fr-latin9\n', x11), ['fr', 'latin9'])
        self.assertEqual(self.keyboard('KEYMAP=de-latin1\n'), ['de'])

    def test_system_setup_is_idempotent(self):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / 'vconsole.conf').write_text('KEYMAP=fr-latin9\n')
            state = Path(tmp) / 'sddm/state.conf'
            state.parent.mkdir()
            state.write_text('[Last]\nSession=\nUser=alex\n')
            for _ in range(2):
                result = self.setup_shell(tmp, 'system_setup')
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((Path(tmp) / 'vconsole.conf').read_text(), 'KEYMAP=fr-latin9\nXKBLAYOUT=fr\n')
            self.assertEqual(state.read_text(),
                             '[Last]\nSession=/usr/share/wayland-sessions/omarchy.desktop\nUser=alex\n')
            self.assertEqual((Path(tmp) / 'sddm.conf.d/10-omarchy-theme.conf').read_text(),
                             '[Theme]\nCurrent=omarchy\n')

    def test_limine_entry(self):
        esp = 'a68aa079-88bd-485e-a1df-12ea34dac556'
        listing = ('BootCurrent: 0005\nBootOrder: 0005,0006,0001\n'
                   'Boot0001* Linux Boot Manager\tHD(2,GPT,8c7f7147,0x800,0x200000)/\\EFI\\systemd\\systemd-bootx64.efi\n'
                   'Boot0005* Limine\tHD(6,GPT,cbcdb443,0x800,0x400000)/\\EFI\\limine\\limine_x64.efi\n'
                   f'Boot0006* Limine\tHD(3,GPT,{esp},0x800,0x400000)/\\EFI\\limine\\limine_x64.efi\n')
        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp) / 'efibootmgr'
            fake.write_text(f"#!/bin/sh\nprintf '%s' '{listing}'\n")
            fake.chmod(0o755)
            for label, expected in (('Limine', '0006'), ('Omarchy', '')):
                result = run('bash', '-c', 'source "$1"; limine_entry "$2" "$3"', 'bash', str(SETUP),
                             label, esp.upper(), env={**os.environ, 'PATH': f'{tmp}:{os.environ["PATH"]}'})
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), expected)

    def test_system_setup_keeps_chosen_session(self):
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp) / 'sddm/state.conf'
            state.parent.mkdir()
            state.write_text('[Last]\nSession=/usr/share/wayland-sessions/plasma.desktop\n')
            result = self.setup_shell(tmp, 'system_setup')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('plasma.desktop', state.read_text())
            self.assertNotIn('omarchy.desktop', state.read_text())

    def test_system_setup_sets_login_user(self):
        # Omarchy's SDDM theme logs in as [Last] User, with no field to type it.
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp) / 'sddm/state.conf'
            for _ in range(2):
                result = self.setup_shell(tmp, 'system_setup alex')
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(state.read_text(),
                             '[Last]\nUser=alex\nSession=/usr/share/wayland-sessions/omarchy.desktop\n')
            result = self.setup_shell(tmp, 'system_setup bob')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('User=alex\n', state.read_text())
            self.assertNotIn('bob', state.read_text())

    def test_system_mode_requires_root(self):
        if os.geteuid() == 0:
            self.skipTest('running as root')
        result = run('bash', str(SETUP), '--system')
        self.assertNotEqual(result.returncode, 0)


class IsoTests(unittest.TestCase):
    def make_live_root(self, root):
        modules = root / 'etc/calamares/modules'
        for directory in (modules, root / 'etc/calamares/scripts', root / 'etc/calamares/images',
                          root / 'usr/share/calamares'):
            directory.mkdir(parents=True)
        (modules / 'packagechooser_desktop.conf').write_text(
            'items:\n    - id: ""\n      name: "No Desktop"\n\n    - id: KDE-Desktop\n      name: "Plasma"\n')
        (modules / 'netinstall.yaml').write_text('- name: "KDE-Desktop"\n  packages:\n    - plasma\n')
        (modules / 'netinstall.conf').write_text(
            '---\ngroupsUrl:\n - https://example.org/netinstall.yaml\n - file:///etc/calamares/modules/netinstall.yaml\n'
            'required: true\n')
        (root / 'usr/share/calamares/settings_online.conf').write_text(
            'instances:\n- id:       online\n  module:   packages\nsequence:\n- exec:\n  - pacstrap\n'
            '  - packages@online\n  - users\n  - shellprocess\n  - umount\n')
        key = root.parent / 'omarchy.asc'
        key.write_text('key\n')
        return key

    def test_customize_is_repeatable(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'airootfs'
            key = self.make_live_root(root)
            aur = Path(tmp) / 'aur'
            aur.mkdir()
            (aur / 'gitkraken-1-1-x86_64.pkg.tar.zst').write_text('package\n')
            for _ in range(2):
                result = run(str(ROOT / 'iso/customize.sh'), '--extras', str(aur), str(root), str(key))
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            modules = root / 'etc/calamares/modules'
            chooser = (modules / 'packagechooser_desktop.conf').read_text()
            self.assertEqual(chooser.count('- id: Omarchy'), 1)
            self.assertLess(chooser.index('- id: Omarchy'), chooser.index('- id: KDE-Desktop'))
            self.assertEqual((modules / 'netinstall.yaml').read_text().count('- omarchy-oncachy-desktop'), 1)
            self.assertNotIn('https://', (modules / 'netinstall.conf').read_text())
            sequence = (root / 'usr/share/calamares/settings_online.conf').read_text().split('sequence:')[1].split()
            self.assertEqual(sequence[sequence.index('packages@online') - 2], 'shellprocess@omarchy_repos')
            self.assertEqual(sequence[sequence.index('shellprocess') + 2], 'shellprocess@omarchy_finish')
            data = root / 'etc/calamares/omarchy-oncachy'
            extras = data / 'extras'
            self.assertTrue((extras / 'aur/gitkraken-1-1-x86_64.pkg.tar.zst').is_file())
            self.assertIn('jetbrains-toolbox', (extras / 'extras.packages').read_text())
            self.assertTrue((extras / 'omarchy-oncachy-extras').stat().st_mode & 0o111)
            self.assertIn('ONCACHY_SERVER=', (data / 'repos.sh').read_text())
            kit = root / 'usr/lib/omarchy-oncachy-iso'
            self.assertTrue((kit / 'iso/customize.sh').stat().st_mode & 0o111)
            hook = (root / 'etc/pacman.d/hooks/90-omarchy-oncachy-calamares.hook').read_text()
            self.assertIn('Target = cachyos-calamares*', hook)
            # The live system runs the kit again after the installer package is upgraded.
            (modules / 'packagechooser_desktop.conf').write_text('items:\n    - id: KDE-Desktop\n')
            result = run('bash', str(kit / 'iso/customize.sh'), str(root), str(kit / 'omarchy.asc'))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertTrue((extras / 'extras.packages').is_file())
            self.assertIn('- id: Omarchy', (modules / 'packagechooser_desktop.conf').read_text())


@unittest.skipUnless(SOURCE, 'Set OMARCHY_TEST_SOURCE to the upstream checkout at the pinned commit')
class UpstreamTests(unittest.TestCase):
    def test_source_is_the_pinned_commit(self):
        result = run('git', '-C', SOURCE, 'rev-parse', 'HEAD')
        self.assertEqual(result.stdout.strip(), pkgbuild_value('echo "$_commit"'))

    def test_desktop_depends_match_upstream_list(self):
        expected = run('bash', str(ROOT / 'bin/desktop-depends.sh'),
                       str(Path(SOURCE) / 'install/omarchy-base.packages')).stdout.split()
        depends = pkgbuild_value('package_omarchy-oncachy-desktop; printf "%s\\n" "${depends[@]}"').split()
        self.assertEqual(depends[0], 'omarchy-oncachy=' + pkgbuild_value('echo "$pkgver-$pkgrel"'))
        self.assertEqual(depends[1:], expected, 'run bin/sync-desktop-depends.sh')

    def test_setup_sources_exist(self):
        # Files omarchy-oncachy-setup copies from /usr/share/omarchy (the skel seed).
        for path in ('config/hypr', 'default/bashrc', 'icon.txt', 'logo.txt', 'default/tensaku/state.toml',
                     'default/hypr/toggles/flags.lua', 'default/nautilus-python/extensions',
                     'bin/omarchy-provision-user', 'bin/omarchy-refresh-applications', 'default/hypr/input.lua'):
            self.assertTrue((Path(SOURCE) / path).exists(), path)
        self.assertIn('vconsole.XKBLAYOUT', (Path(SOURCE) / 'default/hypr/input.lua').read_text())

    def test_package_staging(self):
        with tempfile.TemporaryDirectory(prefix='omarchy package test ') as tmp:
            directory = Path(tmp)
            (directory / 'src').mkdir()
            (directory / 'src/omarchy').symlink_to(Path(SOURCE).resolve(), target_is_directory=True)
            for local in (SETUP, EXTRAS):
                (directory / 'src' / local.name).symlink_to(local)
            (directory / 'tools').mkdir()
            mock = directory / 'tools/magick'
            # Asset generation is mocked; this test checks staging, not image rendering.
            mock.write_text('#!/bin/bash\noutput=${!#}\n: > "${output#PNG32:}"\n')
            mock.chmod(0o755)
            env = {**os.environ, 'srcdir': str(directory / 'src'), 'pkgdir': str(directory / 'pkg'),
                   'pkgname': 'omarchy-oncachy',
                   'PATH': str(directory / 'tools') + ':' + os.environ['PATH']}
            result = run('bash', '-euo', 'pipefail', '-c', 'source "$1"; package_omarchy-oncachy',
                         'bash', str(PKGBUILD), env=env)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            payload = directory / 'pkg'
            self.assertTrue((payload / 'usr/share/omarchy/config/hypr/hyprland.lua').is_file())
            self.assertTrue((payload / 'usr/share/omarchy/shell').is_dir())
            for app in ('foot', 'imv', 'mpv'):
                self.assertTrue((payload / f'usr/share/omarchy/applications/{app}.desktop').is_file())
                self.assertFalse((payload / f'usr/share/applications/{app}.desktop').exists())
            self.assertTrue((payload / 'usr/share/omarchy/application-icons/hicolor').is_dir())
            self.assertFalse((payload / 'usr/share/icons/hicolor').exists())
            self.assertTrue((payload / 'usr/share/wayland-sessions/omarchy.desktop').is_file())
            for asset in ('Main.qml', 'metadata.desktop', 'logo.png'):
                self.assertTrue((payload / 'usr/share/sddm/themes/omarchy' / asset).is_file(), asset)
            for path in ('etc/fastfetch/config.jsonc', 'etc/xdg/kitty/kitty.conf', 'usr/share/pixmaps/omarchy.png',
                         'usr/share/omarchy/default/bashrc', 'usr/share/omarchy/logo.txt'):
                self.assertTrue((payload / path).is_file(), path)
            for command in ('omarchy-update', 'omarchy-oncachy-setup', 'omarchy-oncachy-extras'):
                self.assertTrue((payload / 'usr/bin' / command).stat().st_mode & 0o111, command)
            for forbidden in ('boot', 'etc/mkinitcpio.conf.d', 'etc/limine-entry-tool.d',
                              'etc/pacman.conf', 'etc/os-release', 'etc/sudoers.d', 'etc/pam.d',
                              'etc/sddm.conf', 'etc/sddm.conf.d', 'etc/snapper', 'etc/skel'):
                self.assertFalse((payload / forbidden).exists(), forbidden)
            self.assertNotIn('/user/default-keyring.sh',
                             (payload / 'usr/share/omarchy/install/user/all.sh').read_text())
            self.assertNotIn('omarchy-migrate', (payload / 'usr/bin/omarchy-update').read_text())


if __name__ == '__main__':
    unittest.main()
