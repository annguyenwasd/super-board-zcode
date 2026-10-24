#!/usr/bin/env python3
"""Exercise the resolver's public CLI against isolated host installations."""
import json
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

KIT = Path(__file__).resolve().parents[1]
CLI = KIT / 'scripts/super-board-skills-ready.py'
CORE = ['super-board','super-build','super-qa','super-review','super-collect','visual','git-sync','ui-refine-loop']

class Readiness(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'project'
        self.home = Path(self.temp.name) / 'home'
        self.root.mkdir(); self.home.mkdir()
        self.card = dict(number=1, status='Ready', labels=['feature'], body='')

    def put(self, name, host='zcode', root=None, text='skill instructions'):
        folder = '.agents/skills' if host == 'agents' else '.zcode/skills'
        path = (root or self.root) / folder / name / 'SKILL.md'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def full(self, host='zcode'):
        names = CORE + ['tdd', 'implement', 'codebase-design', 'code-review', 'diagnosing-bugs',
                               'verification-before-completion', 'testing-strategy']
        for name in names:
            self.put(name, host)

    def run_cli(self, host='zcode', cards=None, extra=(), expected=0):
        process = subprocess.run([sys.executable, str(CLI), '--root', str(self.root), '--host', host,
                                  '--home', str(self.home), '--cards', '-', *extra],
                                 input=json.dumps([self.card] if cards is None else cards), text=True, capture_output=True)
        self.assertEqual(process.returncode, expected, process.stderr)
        return json.loads(process.stdout) if process.stdout else process.stderr

    def test_complete_partial_lock_and_grilling_are_distinct(self):
        (self.root / 'skills-lock.json').write_text('{"mattpocock/skills":true}')
        self.put('grilling'); self.put('tdd')
        self.assertFalse(self.run_cli(expected=10)['ready'])
        self.full()
        result = self.run_cli()
        self.assertTrue(result['ready'])
        self.assertEqual(next(e for e in result['entries'] if e['name'] == 'ponytail:ponytail')['status'], 'fallback')
        self.assertEqual(next(e for e in result['entries'] if e['name'] == 'vitest')['status'], 'skipped')
        (self.root / '.zcode/skills/code-review/SKILL.md').unlink()
        self.assertIn('mattpocock-skills:code-review', [e['name'] for e in self.run_cli(expected=10)['entries'] if e['status'] == 'missing'])

    def test_skills_symlinked_into_agents_resolve(self):
        self.full()
        real = self.root / 'shared/skills/tdd/SKILL.md'
        real.parent.mkdir(parents=True); real.write_text('via a shared tree')
        shutil.rmtree(self.root / '.zcode/skills/tdd')
        directory = self.root / '.agents/skills'; directory.mkdir(parents=True)
        (directory / 'tdd').symlink_to(self.root / 'shared/skills/tdd', target_is_directory=True)
        result = self.run_cli()
        self.assertTrue(all(Path(e['resolved_path']).is_file() for e in result['entries'] if e['status'] == 'resolved'))

    def test_empty_unreadable_broken_and_directory_are_missing(self):
        self.full()
        path = self.root / '.zcode/skills/code-review/SKILL.md'
        path.write_text(' \n'); self.run_cli(expected=10)
        path.write_text('instructions'); path.chmod(0); self.run_cli(expected=10)
        path.chmod(0o644); path.unlink(); path.symlink_to(self.root / 'missing'); self.run_cli(expected=10)
        path.unlink(); path.mkdir(); self.run_cli(expected=10)

    def test_user_roots(self):
        self.full()
        path = self.root / '.zcode/skills/code-review/SKILL.md'; path.unlink()
        user = self.put('code-review', root=self.home)
        result = self.run_cli()
        self.assertEqual(next(e['resolved_path'] for e in result['entries'] if e['name'] == 'mattpocock-skills:code-review'), str(user.resolve()))

    def test_override_keeps_boundaries_and_unknown_namespace_exact(self):
        self.full()
        self.card['body'] = '```\nSkills: ignored\n```\nSkills: `custom`\n'
        self.put('custom'); self.run_cli()
        (self.root / '.zcode/skills/implement/SKILL.md').unlink()
        result = self.run_cli()
        self.assertNotIn('mattpocock-skills:implement', [e['name'] for e in result['entries']])
        self.card['body'] = 'Skills: vendor:tdd'
        self.run_cli(expected=10)
        catalog = self.root / 'active.json'
        path = self.put('custom')
        catalog.write_text(json.dumps(dict(host='zcode', skills=[dict(name='vendor:tdd', path=str(path), enabled=True, scope='project', project_root=str(self.root))])))
        self.run_cli(extra=['--catalog', str(catalog)])
        self.card['body'] = 'Skills:'
        self.run_cli()

    def test_docs_and_label_precedence(self):
        self.full()
        self.card['labels'] = ['docs']
        result = self.run_cli(extra=['--lane', 'build'])
        self.assertNotIn('mattpocock-skills:tdd', [e['name'] for e in result['entries']])
        self.card['labels'] = ['feature', 'bug']
        result = self.run_cli(extra=['--lane', 'build'])
        names = [e['name'] for e in result['entries']]
        self.assertIn('mattpocock-skills:diagnosing-bugs', names)
        self.assertNotIn('mattpocock-skills:implement', names)

    def test_empty_selection_conditional_activation_and_no_fallback(self):
        self.run_cli(cards=[])
        self.full()
        self.run_cli(extra=['--require', 'vitest'], expected=10)
        self.put('vitest'); self.run_cli(extra=['--require', 'vitest'])
        self.card['body'] = 'Skills: nonexistent'
        self.run_cli(expected=10)

    def test_bad_override_and_missing_body_are_input_errors(self):
        self.full()
        for body in ['Skills: tdd,', 'Skills: ../tdd', 'Skills: /tdd', 'Skills: tdd\nSkills: implement',
                     'Skills: mattpocock-skills:grilling']:
            self.card['body'] = body
            self.run_cli(expected=64)
        self.card.update(body='Skills: mattpocock-skills:improve-codebase-architecture', status='Review')
        self.run_cli(expected=64)
        self.card.update(status='Ready')
        self.put('improve-codebase-architecture')
        self.run_cli(extra=['--lane','build'])
        del self.card['body']; self.run_cli(expected=64)

    def test_qa_and_review_have_their_own_chain(self):
        self.full()
        (self.root / '.zcode/skills/implement/SKILL.md').unlink()
        self.card['labels'] = ['qa']
        result = self.run_cli()
        self.assertNotIn('build', [e['lane'] for e in result['entries']])
        self.card['body'] = 'Skills: custom'; self.run_cli(expected=10)
        self.put('custom'); self.run_cli()
        self.card.update(status='Review', labels=[], body='')
        (self.root / '.zcode/skills/tdd/SKILL.md').unlink()
        result = self.run_cli()
        self.assertEqual(next(e['status'] for e in result['entries'] if e['name'] == 'ponytail:ponytail-review'), 'fallback')

    def test_catalog_disabled_and_cross_project_do_not_satisfy(self):
        self.full()
        (self.root / '.zcode/skills/code-review/SKILL.md').unlink()
        external = self.root / 'external/SKILL.md'; external.parent.mkdir(); external.write_text('instructions')
        catalog = self.root / 'active.json'
        entry = dict(name='mattpocock-skills:code-review', path=str(external), enabled=False, scope='user')
        catalog.write_text(json.dumps(dict(host='zcode', skills=[entry])))
        self.run_cli(extra=['--catalog', str(catalog)], expected=10)
        entry.update(enabled=True, scope='project', project_root=str(self.home))
        catalog.write_text(json.dumps(dict(host='zcode', skills=[entry])))
        self.run_cli(extra=['--catalog', str(catalog)], expected=10)
        entry.update(project_root=str(self.root))
        interactive = dict(name='mattpocock-skills:grilling', path=str(external), enabled=True, scope='user')
        catalog.write_text(json.dumps(dict(host='zcode', skills=[entry, interactive])))
        self.run_cli(extra=['--catalog', str(catalog)])
        catalog.write_text('{"host":"zcode","skills":{}}')
        self.run_cli(extra=['--catalog', str(catalog)], expected=64)

    def test_ordered_literal_policy_rows_and_activation_boundaries(self):
        self.full()
        cases = [(['bug'], ['mattpocock-skills:diagnosing-bugs','mattpocock-skills:tdd']),
                 (['feature'], ['mattpocock-skills:implement','mattpocock-skills:tdd','mattpocock-skills:codebase-design']),
                 (['ux'], ['mattpocock-skills:implement','mattpocock-skills:tdd']),
                 (['refactor'], ['mattpocock-skills:codebase-design','mattpocock-skills:tdd']),
                 (['tech-debt'], ['mattpocock-skills:codebase-design','mattpocock-skills:tdd']),
                 (['tests'], ['mattpocock-skills:tdd']), (['docs'], [])]
        for labels, expected in cases:
            self.card['labels'] = labels
            result = self.run_cli(extra=['--lane','build'])
            names = [e['name'] for e in result['entries'] if e['requirement']=='required']
            self.assertEqual(names, ['super-board','super-build', *expected, 'ponytail:ponytail','verification-before-completion','mattpocock-skills:code-review'])
        # A docs chain can be ready while a proposed feature chain is incomplete.
        (self.root / '.zcode/skills/implement/SKILL.md').unlink()
        self.card['labels'] = ['docs']; self.run_cli()
        self.card['labels'] = ['feature']; self.run_cli(expected=10)
        self.card['labels'] = ['docs']; self.run_cli(extra=['--require','verify-example'], expected=10)
        self.put('verify-example'); self.run_cli(extra=['--require','verify-example'])

    def test_discovery_stops_at_independent_repository_root(self):
        self.full('agents')
        subprocess.run(['git','init','-q',str(self.root)], check=True)
        path = self.root / '.agents/skills/tdd/SKILL.md'; path.unlink()
        outside = self.root.parent / '.agents/skills/tdd/SKILL.md'
        outside.parent.mkdir(parents=True); outside.write_text('outside owning repository')
        self.run_cli(expected=10)
        nested = self.root / 'nested'; nested.mkdir()
        self.root = nested
        # The project root is still visible from an in-repository subdirectory.
        path.write_text('in owning repository')
        self.run_cli()

    def test_setup_union_reports_every_unconditional_requirement(self):
        self.full()
        process = subprocess.run([sys.executable, str(CLI), '--root', str(self.root), '--host', 'zcode', '--home', str(self.home), '--profile', 'setup'], text=True, capture_output=True)
        self.assertEqual(process.returncode, 0, process.stderr)
        result = json.loads(process.stdout)
        for name in CORE:
            self.assertIn(name, [e['name'] for e in result['entries']])
        self.assertTrue(any(e['name'] == 'mattpocock-skills:diagnosing-bugs' and e['requirement'] == 'required' for e in result['entries']))

if __name__ == '__main__':
    unittest.main()
