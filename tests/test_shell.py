import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ShellTests(unittest.TestCase):
    def test_missing_dependencies_and_configured_control(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary)
            zsh_root = home / '.oh-my-zsh'
            env = dict(os.environ, HOME=str(home), ZSH=str(zsh_root),
                       ZSH_CUSTOM=str(zsh_root / 'custom'), PATH='/usr/bin:/bin')
            script = 'source "$1"; print "omz=${review_omz:-absent} prompt=${review_prompt:-absent}"; print -l $plugins'
            command = ['/bin/zsh', '-dfc', script, 'review', str(ROOT / 'zsh/.zshrc')]
            missing = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(missing.returncode, 0)
            self.assertEqual(missing.stderr, '')
            self.assertIn('omz=absent prompt=absent', missing.stdout)
            self.assertNotIn('zsh-autosuggestions', missing.stdout)
            zsh_root.mkdir()
            (zsh_root / 'oh-my-zsh.sh').write_text('review_omz=loaded; p10k() { :; }\n')
            (home / '.p10k.zsh').write_text('review_prompt=loaded\n')
            plugin = zsh_root / 'custom/plugins/zsh-autosuggestions'
            plugin.mkdir(parents=True)
            (plugin / 'zsh-autosuggestions.plugin.zsh').touch()
            configured = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(configured.returncode, 0)
            self.assertEqual(configured.stderr, '')
            self.assertIn('omz=loaded prompt=loaded', configured.stdout)
            self.assertIn('zsh-autosuggestions', configured.stdout)

    def test_dependency_bootstrap_with_stubs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            home = root / 'home'
            home.mkdir()
            mocks = root / 'bin'
            mocks.mkdir()
            scripts = {
                'brew': '#!/bin/bash\nexit 0\n',
                'stow': '#!/bin/bash\nexit 0\n',
                'git': '''#!/bin/bash
[ "$1" = clone ] || exit 9
repo=$3 dest=$4
mkdir -p "$dest"
case "$repo" in
  */ohmyzsh.git) touch "$dest/oh-my-zsh.sh" ;;
  */powerlevel10k.git) touch "$dest/powerlevel10k.zsh-theme" ;;
  */zsh-autosuggestions.git) touch "$dest/zsh-autosuggestions.plugin.zsh" ;;
  */zsh-syntax-highlighting.git) touch "$dest/zsh-syntax-highlighting.plugin.zsh" ;;
  *) exit 10 ;;
esac
printf '%s\\n' "$repo" >> "$REVIEW_CLONES"
''',
            }
            for name, content in scripts.items():
                path = mocks / name
                path.write_text(content)
                path.chmod(0o755)
            log = root / 'clones'
            env = dict(os.environ, HOME=str(home), PATH=f'{mocks}:/usr/bin:/bin',
                       ZSH=str(home / '.oh-my-zsh'), ZSH_CUSTOM=str(home / '.oh-my-zsh/custom'),
                       REVIEW_CLONES=str(log))
            command = ['/bin/bash', str(ROOT / 'scripts/install-dependencies.sh')]
            result = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            # Third-party checkouts belong to vendor.ini; this step must never clone.
            self.assertFalse(log.exists())
            self.assertFalse((home / '.oh-my-zsh').exists())

if __name__ == '__main__':
    unittest.main()
