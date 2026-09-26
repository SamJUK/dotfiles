import contextlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[1] / 'scripts/install-links.py'
spec = importlib.util.spec_from_file_location('installer', MODULE)
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.home = self.base / 'home'
        self.home.mkdir()
        self.public = self.base / 'public'
        self.private = self.base / 'private'
        self.work = self.base / 'work'
        for name in installer.PACKAGES:
            (self.public / name).mkdir(parents=True)
        self.write(self.public / 'zsh/.zshrc', 'public shell\n')
        self.write(self.public / 'git/.gitconfig', '[include]\n    path = ~/.config/git/shared.gitconfig\n')
        self.write(self.public / 'git/.config/git/shared.gitconfig', '[alias]\n    st = status\n')
        self.write(self.public / 'agents/.agents/AGENTS.md', 'Shared instructions\n')
        self.write(self.public / 'agents/.agents/skills/example/SKILL.md', 'Public skill\n')
        self.write(self.public / 'claude/.claude/CLAUDE.md', '@~/.agents/AGENTS.md\n')
        self.write(self.private / '.stow-packages', 'agents\n')
        self.write(self.private / 'agents/.agents/rules/personal.md', 'Private rules\n')
        self.write(self.work / 'AGENTS.md', 'Work rules\n')
        self.write(self.work / 'skills/work-example/SKILL.md', 'Work skill\n')
        self.addCleanup(patch.stopall)
        patch.object(installer, 'PUBLIC', self.public).start()
        patch.dict(os.environ, {'HOME': str(self.home)}).start()

    def write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def plan(self):
        return installer.build(self.home, self.private, self.work)

    def apply(self, plan):
        with contextlib.redirect_stdout(io.StringIO()):
            plan.apply()

    def test_clean_install_and_reinstall(self):
        self.apply(self.plan())
        self.assertEqual((self.home / '.zshrc').read_text(), 'public shell\n')
        self.assertEqual((self.home / '.agents/rules/bed.md').read_text(), 'Work rules\n')
        self.assertEqual((self.home / '.claude/skills/example/SKILL.md').read_text(), 'Public skill\n')
        self.assertFalse((self.home / '.gitconfig').is_symlink())
        repeated = self.plan()
        self.assertTrue(all(i['action'] == 'unchanged' for i in repeated.entries.values()))
        self.apply(repeated)

    def test_overlapping_overlays_fail_before_mutation(self):
        self.write(self.private / 'agents/.agents/AGENTS.md', 'Collision\n')
        with self.assertRaisesRegex(ValueError, 'Two sources'):
            self.plan()
        self.assertEqual(list(self.home.iterdir()), [])
        (self.private / 'agents/.agents/AGENTS.md').unlink()
        self.apply(self.plan())
        self.assertTrue((self.home / '.agents/AGENTS.md').is_file())

    def test_keep_existing_file_with_other_links_installed(self):
        self.write(self.home / '.zshrc', 'User shell\n')
        plan = self.plan()
        plan.entries[self.home / '.zshrc']['action'] = 'keep'
        self.apply(plan)
        self.assertEqual((self.home / '.zshrc').read_text(), 'User shell\n')
        self.assertTrue((self.home / '.agents/rules/personal.md').is_symlink())

    def test_replacement_backs_up_symlink_without_touching_target(self):
        target = self.base / 'old-shell'
        target.write_text('Original\n')
        (self.home / '.zshrc').symlink_to(target)
        plan = self.plan()
        plan.entries[self.home / '.zshrc']['action'] = 'replace'
        self.apply(plan)
        self.assertEqual(target.read_text(), 'Original\n')
        self.assertTrue((plan.backup / '1').is_symlink())
        self.assertEqual((self.home / '.zshrc').read_text(), 'public shell\n')

    def test_instructions_are_preserved_and_backed_up(self):
        self.write(self.home / '.codex/AGENTS.md', 'My instructions\n')
        plan = self.plan()
        self.apply(plan)
        self.assertTrue((self.home / '.codex/AGENTS.md').read_text().startswith('My instructions\n'))
        self.assertEqual((plan.backup / '1').read_text(), 'My instructions\n')
        self.assertTrue(all(i['action'] == 'unchanged' for i in self.plan().entries.values()))

    def test_custom_claude_directory(self):
        custom = self.base / 'custom-rules'
        custom.mkdir()
        (custom / 'unrelated.md').write_text('Unrelated\n')
        (self.home / '.claude').mkdir()
        (self.home / '.claude/rules').symlink_to(custom)
        self.apply(self.plan())
        self.assertEqual((custom / 'bed.md').read_text(), 'Work rules\n')
        self.assertEqual((custom / 'unrelated.md').read_text(), 'Unrelated\n')
        self.assertTrue((self.home / '.claude/rules').is_symlink())
        self.assertFalse((custom / 'rules').exists())

    def test_canonical_claude_directory_links(self):
        for name in ('skills', 'rules'):
            (self.home / '.agents' / name).mkdir(parents=True)
            (self.home / '.claude').mkdir(exist_ok=True)
            (self.home / '.claude' / name).symlink_to(self.home / '.agents' / name)
        self.apply(self.plan())
        self.assertTrue((self.home / '.claude/rules/bed.md').is_file())
        self.assertFalse((self.home / '.agents/rules/rules').exists())
        self.assertTrue(all(i['action'] == 'unchanged' for i in self.plan().entries.values()))

    def test_parent_file_and_changed_destination_fail_before_mutation(self):
        (self.home / '.agents').write_text('blocked')
        with self.assertRaisesRegex(ValueError, 'Parent is not a directory'):
            self.plan()
        (self.home / '.agents').unlink()
        plan = self.plan()
        (self.home / '.zshrc').write_text('Changed after preview\n')
        with self.assertRaisesRegex(ValueError, 'Changed since preview'):
            self.apply(plan)
        self.assertFalse((self.home / '.agents').exists())
        self.assertEqual((self.home / '.zshrc').read_text(), 'Changed after preview\n')

    def test_skill_ownership_includes_disjoint_files(self):
        self.write(self.private / 'agents/.agents/skills/example/extra.md', 'Separate file\n')
        with self.assertRaisesRegex(ValueError, 'Skill example belongs to both'):
            self.plan()
        self.assertEqual(list(self.home.iterdir()), [])

    def test_existing_skill_directory_symlink(self):
        (self.home / '.agents/skills').mkdir(parents=True)
        (self.home / '.agents/skills/example').symlink_to(self.public / 'agents/.agents/skills/example')
        plan = self.plan()
        self.assertFalse(any(i['action'] == 'conflict' for i in plan.entries.values()))
        self.apply(plan)
        self.assertEqual((self.home / '.agents/skills/example/SKILL.md').read_text(), 'Public skill\n')

    def test_custom_agents_directory_and_foreign_skill_link(self):
        custom = self.base / 'custom-skills'
        custom.mkdir()
        (self.home / '.agents').mkdir()
        (self.home / '.agents/skills').symlink_to(custom)
        self.apply(self.plan())
        self.assertEqual((custom / 'example/SKILL.md').read_text(), 'Public skill\n')
        self.assertTrue((self.home / '.agents/skills').is_symlink())
        self.assertTrue(all(i['action'] == 'unchanged' for i in self.plan().entries.values()))

    def test_instruction_mode_and_failed_apply_restore(self):
        instructions = self.home / '.codex/AGENTS.md'
        self.write(instructions, 'Private instructions\n')
        instructions.chmod(0o600)
        plan = self.plan()
        self.apply(plan)
        self.assertEqual(instructions.stat().st_mode & 0o777, 0o600)
        (self.home / '.zshrc').unlink()
        self.write(self.home / '.zshrc', 'Original shell\n')
        plan = self.plan()
        plan.entries[self.home / '.zshrc']['action'] = 'replace'
        with patch.object(installer.subprocess, 'run', side_effect=OSError('simulated failure')):
            with self.assertRaisesRegex(OSError, 'simulated failure'):
                self.apply(plan)
        self.assertEqual((self.home / '.zshrc').read_text(), 'Original shell\n')
        plan = self.plan()
        plan.entries[self.home / '.zshrc']['action'] = 'replace'
        self.apply(plan)
        self.assertEqual((self.home / '.zshrc').read_text(), 'public shell\n')

    def test_bulk_conflict_choices_keep_and_replace(self):
        self.write(self.home / '.zshrc', 'User shell\n')
        self.write(self.home / '.agents/AGENTS.md', 'User instructions\n')
        plan = self.plan()
        with patch('builtins.input', return_value='k'):
            plan.resolve()
        self.apply(plan)
        self.assertEqual((self.home / '.zshrc').read_text(), 'User shell\n')
        self.assertEqual((self.home / '.agents/AGENTS.md').read_text(), 'User instructions\n')
        self.assertEqual((self.home / '.agents/rules/bed.md').read_text(), 'Work rules\n')
        plan = self.plan()
        with patch('builtins.input', return_value='b'):
            plan.resolve()
        self.apply(plan)
        self.assertEqual((self.home / '.zshrc').read_text(), 'public shell\n')
        self.assertEqual((self.home / '.agents/AGENTS.md').read_text(), 'Shared instructions\n')
        self.assertEqual(len(plan.saved), 2)


    def test_codex_instructions_linked_when_absent_or_already_wired(self):
        self.apply(self.plan())
        codex = self.home / '.codex/AGENTS.md'
        self.assertTrue(codex.is_symlink())
        self.assertEqual(codex.read_text(), 'Shared instructions\n')
        codex.unlink()
        codex.symlink_to('../.agents/AGENTS.md')
        plan = self.plan()
        self.assertNotIn(installer.physical(codex), plan.entries)
        self.apply(plan)
        self.assertEqual(os.readlink(codex), '../.agents/AGENTS.md')

    def test_existing_claude_import_is_not_duplicated(self):
        self.write(self.home / '.claude/CLAUDE.md', 'Mine\n@~/.agents/AGENTS.md\n')
        plan = self.plan()
        self.assertNotIn(installer.physical(self.home / '.claude/CLAUDE.md'), plan.entries)
        self.apply(plan)
        self.assertEqual((self.home / '.claude/CLAUDE.md').read_text(), 'Mine\n@~/.agents/AGENTS.md\n')


    def upstream(self):
        repo = self.base / 'upstream'
        run = lambda *a: subprocess.run(['git', '-C', str(repo), *a], check=True, capture_output=True, text=True).stdout.strip()
        repo.mkdir()
        run('init', '-q')
        run('config', 'uploadpack.allowAnySHA1InWant', 'true')
        shas = []
        for text in ('Vendor v1\n', 'Vendor v2\n'):
            self.write(repo / 'skills/vendored/SKILL.md', text)
            self.write(repo / 'README.md', 'not wanted\n')
            run('add', '-A')
            run('-c', 'user.name=t', '-c', 'user.email=t@t', '-c', 'commit.gpgsign=false', 'commit', '-q', '-m', text)
            shas.append(run('rev-parse', 'HEAD'))
        return repo, shas

    def manifest(self, repo, sha, dest='.agents/skills/vendored', path='skills/vendored', where=None):
        link = '' if dest == '-' else f'link = {dest}\n'
        self.write((where or self.public) / 'vendor.ini',
                   f'[vendored]\nurl = file://{repo}\ncommit = {sha}\npath = {path}\n{link}')

    def test_vendor_pinned_fetch_link_and_update(self):
        repo, (v1, v2) = self.upstream()
        self.manifest(repo, v1)
        plan = self.plan()
        self.assertEqual(plan.vendored['vendored']['action'], 'fetch')
        self.apply(plan)
        skill = self.home / '.agents/skills/vendored/SKILL.md'
        self.assertEqual(skill.read_text(), 'Vendor v1\n')
        self.assertEqual((self.home / '.claude/skills/vendored/SKILL.md').read_text(), 'Vendor v1\n')
        checkout = self.home / installer.VENDOR_DIR / 'vendored'
        self.assertFalse((checkout / 'README.md').exists())
        repeated = self.plan()
        self.assertEqual(repeated.vendored['vendored']['action'], 'unchanged')
        self.assertTrue(all(i['action'] == 'unchanged' for i in repeated.entries.values()))
        self.manifest(repo, v2)
        bumped = self.plan()
        self.assertEqual(bumped.vendored['vendored']['action'], 'update')
        self.apply(bumped)
        self.assertEqual(skill.read_text(), 'Vendor v2\n')

    def test_vendor_fetch_only_and_rejections(self):
        repo, (v1, _) = self.upstream()
        self.manifest(repo, v1, dest='-', path='.')
        self.apply(self.plan())
        self.assertTrue((self.home / installer.VENDOR_DIR / 'vendored/README.md').is_file())
        (self.home / installer.VENDOR_DIR / 'vendored/README.md').write_text('local edit\n')
        with self.assertRaisesRegex(ValueError, 'Local changes'):
            self.plan()
        self.manifest(repo, 'abc123')
        with self.assertRaisesRegex(ValueError, '40-character'):
            self.plan()
        self.manifest(repo, v1, dest='../escape')
        with self.assertRaisesRegex(ValueError, 'stay inside'):
            self.plan()
        self.write(self.public / 'vendor.ini',
                   f'[vendored]  # comment\nurl = file://{repo}  # upstream\ncommit = {v1}  # pinned\n')
        self.assertEqual(installer.read_manifest(self.public)[0]['sha'], v1)
        self.write(self.public / 'vendor.ini', f'[vendored]\nurl = file://{repo}\ncommit = {v1}\nlnik = typo\n')
        with self.assertRaisesRegex(ValueError, 'unknown keys lnik'):
            self.plan()

    def test_vendor_skill_clash_and_bad_sha_fail_before_mutation(self):
        repo, (v1, _) = self.upstream()
        self.manifest(repo, v1, dest='.agents/skills/example')
        with self.assertRaisesRegex(ValueError, 'belongs to both'):
            self.plan()
        self.manifest(repo, '0' * 40)
        with self.assertRaises(subprocess.CalledProcessError):
            self.apply(self.plan())
        self.assertFalse((self.home / '.zshrc').exists())


if __name__ == '__main__':
    unittest.main()
