import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PKGBUILD = ROOT / 'pkgbuilds/omarchy-oncachy/PKGBUILD'
SETUP = ROOT / 'pkgbuilds/omarchy-oncachy/omarchy-oncachy-setup'
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
        for path in [*ROOT.glob('bin/*.sh'), PKGBUILD, SETUP]:
            result = run('bash', '-n', str(path))
            self.assertEqual(result.returncode, 0, f'{path}: {result.stderr}')

    def test_version_matches_tag(self):
        tag = pkgbuild_value('echo "$_tag"')
        self.assertEqual(pkgbuild_value('echo "$pkgver"'), tag.removeprefix('v').replace('-', ''))
        self.assertRegex(pkgbuild_value('echo "$_commit"'), r'^[0-9a-f]{40}$')
        self.assertIn('#commit=$_commit', PKGBUILD.read_text())

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

    def test_system_setup_keeps_chosen_session(self):
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp) / 'sddm/state.conf'
            state.parent.mkdir()
            state.write_text('[Last]\nSession=/usr/share/wayland-sessions/plasma.desktop\n')
            result = self.setup_shell(tmp, 'system_setup')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('plasma.desktop', state.read_text())
            self.assertNotIn('omarchy.desktop', state.read_text())

    def test_system_mode_requires_root(self):
        if os.geteuid() == 0:
            self.skipTest('running as root')
        result = run('bash', str(SETUP), '--system')
        self.assertNotEqual(result.returncode, 0)


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
            (directory / 'src/omarchy-oncachy-setup').symlink_to(SETUP)
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
            for path in ('etc/fastfetch/config.jsonc', 'etc/xdg/kitty/kitty.conf', 'usr/share/pixmaps/omarchy.png',
                         'usr/share/omarchy/default/bashrc', 'usr/share/omarchy/logo.txt'):
                self.assertTrue((payload / path).is_file(), path)
            for command in ('omarchy-update', 'omarchy-oncachy-setup'):
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
