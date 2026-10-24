#!/usr/bin/env python3
"""Lane worktree path contract: the guard allows only .zcode/worktrees, and
cleanup-wt removes merged lane worktrees while preserving everything else.
No live workers or GitHub."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

PACK = Path(__file__).resolve().parents[1]


class WorktreePaths(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve() / "repo"
        self.root.mkdir()
        self.env = dict(os.environ, GIT_AUTHOR_NAME="test", GIT_AUTHOR_EMAIL="test@example.com",
                        GIT_COMMITTER_NAME="test", GIT_COMMITTER_EMAIL="test@example.com",
                        CLEANUP_WT_GH="/nonexistent")
        self.run_cmd("git", "init", "-q", "-b", "main")
        (self.root / ".gitignore").write_text(".zcode/worktrees/\n.worktrees/\n")
        self.run_cmd("git", "add", ".gitignore")
        self.run_cmd("git", "commit", "-qm", "fixture")
        self.run_cmd("git", "remote", "add", "origin", str(self.root))

    def run_cmd(self, *cmd, cwd=None, input=None, check=True):
        return subprocess.run(cmd, cwd=cwd or self.root, env=self.env, input=input,
                              text=True, capture_output=True, check=check)

    def guard(self, command):
        payload = json.dumps({"tool_name": "Bash", "cwd": str(self.root),
                              "tool_input": {"command": command}})
        return self.run_cmd("python3", str(PACK / "hooks/guard-worktree-path.py"),
                            input=payload, check=False)

    def guard_denies(self, command):
        result = self.guard(command)
        return result.returncode == 0 and '"permissionDecision": "deny"' in result.stdout

    def test_guard_allows_canonical_lane_paths_only(self):
        for lane in ("build", "qa", "review"):
            with self.subTest(lane=lane):
                path = f".zcode/worktrees/issue-7-{lane}"
                command = f"git worktree add -b issue-7-{lane} {shlex.quote(path)} main"
                self.assertEqual(self.guard(command).stdout, "",
                                 "the guard must allow the canonical lane worktree path")
        for command in ("git worktree add -b issue-7 .worktrees/issue-7 main",
                        "git worktree add -b issue-7 /tmp/issue-7 main",
                        "git worktree add -b issue-7 worktrees/issue-7 main",
                        "git worktree add ../issue-7-outside"):
            with self.subTest(command=command):
                self.assertTrue(self.guard_denies(command),
                                "the guard must block non-canonical paths")

    def test_lane_worktree_is_cleaned_after_merge(self):
        path = self.root / ".zcode/worktrees/issue-7-build"
        command = "git worktree add -b issue-7-build " + shlex.quote(str(path)) + " main"
        self.run_cmd(*shlex.split(command))
        (path / "work.txt").write_text("done")
        self.run_cmd("git", "add", "-A", cwd=path)
        self.run_cmd("git", "commit", "-qm", "work", cwd=path)
        self.run_cmd("git", "push", "-q", "origin", "issue-7-build", cwd=path)
        self.run_cmd("git", "merge", "-q", "--ff-only", "issue-7-build")
        for meta in (self.root / ".git/worktrees").iterdir():
            for name in ("gitdir", "commondir"):
                os.utime(meta / name, (1577836800, 1577836800))
        self.run_cmd("python3", str(PACK / "hooks/cleanup-wt.py"), "--post-merge",
                     "--no-fetch", "--base", "main", input="")
        self.assertFalse(path.exists(), "cleanup must remove the merged lane worktree")

    def test_cleanup_keeps_dirty_and_unregistered_folders(self):
        dirty = self.root / ".zcode/worktrees/issue-8-build"
        self.run_cmd("git", "worktree", "add", "-b", "issue-8", str(dirty), "main")
        (dirty / "unfinished.txt").write_text("keep this work")
        for name in ("issue-7-build", "another-agent"):
            path = self.root / ".zcode/worktrees" / name
            path.mkdir(parents=True)
            (path / "unfinished.txt").write_text("keep this work")
        for meta in (self.root / ".git/worktrees").iterdir():
            for name in ("gitdir", "commondir"):
                os.utime(meta / name, (1577836800, 1577836800))
        self.run_cmd("python3", str(PACK / "hooks/cleanup-wt.py"), "--post-merge",
                     "--no-fetch", "--base", "main", input="")
        self.assertEqual((dirty / "unfinished.txt").read_text(), "keep this work")
        for name in ("issue-7-build", "another-agent"):
            self.assertEqual((self.root / ".zcode/worktrees" / name / "unfinished.txt").read_text(),
                             "keep this work")

    def test_cleanup_keeps_detached_commits(self):
        path = self.root / ".zcode/worktrees/issue-7-build"
        self.run_cmd("git", "worktree", "add", "--detach", str(path), "main")
        self.run_cmd("git", "commit", "--allow-empty", "-qm", "unreferenced work", cwd=path)
        for meta in (self.root / ".git/worktrees").iterdir():
            for name in ("gitdir", "commondir"):
                os.utime(meta / name, (1577836800, 1577836800))
        self.run_cmd("python3", str(PACK / "hooks/cleanup-wt.py"), "--post-merge",
                     "--no-fetch", "--base", "main", input="")
        self.assertTrue(path.exists(), "detached commits need their existing worktree HEAD")
        self.assertEqual(self.run_cmd("git", "log", "-1", "--format=%s", cwd=path).stdout.strip(),
                         "unreferenced work")


if __name__ == "__main__":
    unittest.main()
