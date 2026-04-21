#!/usr/bin/env python3
"""Quick agent-status probe for Claude Code multi-agent refactors.

Prints:
- Trunk HEAD + recent-commit stats (absolute + since-last-check delta)
- Active worktrees (count, locked, ahead of trunk)
- Heartbeats in main repo (triggered/active/stale/wedged/completed)
- Heartbeats per worktree (triggered/active/stale/wedged/completed)

Reusable: defaults target Seshat's central-layers layout but are overridable
via CLI flags. Assumes the "heartbeat contract" convention: agents write a
markdown file to <heartbeat_dir> and delete it on successful completion.

Last-check state is persisted in /tmp/agents_status_<repo-hash>.txt so the
script can show "since last check" commit deltas across invocations.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path


# --- Color ---------------------------------------------------------------

class Color:
    """ANSI color helpers. Disabled when stdout isn't a TTY, NO_COLOR is set,
    or --no-color is passed. Safe no-op when disabled."""
    enabled = False

    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    CYAN = "\033[36m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    RED = "\033[31m"
    BLUE = "\033[34m"

    @classmethod
    def configure(cls, force_off: bool = False) -> None:
        if force_off:
            cls.enabled = False
            return
        if os.environ.get("NO_COLOR"):
            cls.enabled = False
            return
        cls.enabled = sys.stdout.isatty()

    @classmethod
    def _wrap(cls, text: str, code: str) -> str:
        return f"{code}{text}{cls.RESET}" if cls.enabled else text

    @classmethod
    def header(cls, s: str) -> str: return cls._wrap(s, cls.BOLD + cls.CYAN)
    @classmethod
    def bold(cls, s: str) -> str: return cls._wrap(s, cls.BOLD)
    @classmethod
    def dim(cls, s: str) -> str: return cls._wrap(s, cls.DIM)
    @classmethod
    def good(cls, s: str) -> str: return cls._wrap(s, cls.GREEN)
    @classmethod
    def warn(cls, s: str) -> str: return cls._wrap(s, cls.YELLOW)
    @classmethod
    def bad(cls, s: str) -> str: return cls._wrap(s, cls.RED)
    @classmethod
    def sha(cls, s: str) -> str: return cls._wrap(s, cls.YELLOW)
    @classmethod
    def info(cls, s: str) -> str: return cls._wrap(s, cls.BLUE)

    @classmethod
    def tag(cls, tag_name: str) -> str:
        colors = {"active": cls.good, "stale": cls.warn, "wedged": cls.bad}
        fn = colors.get(tag_name, cls.dim)
        return fn(tag_name)


# --- Config --------------------------------------------------------------

DEFAULT_HEARTBEAT_DIR = ".codex-heartbeat"
DEFAULT_WORKTREE_ROOT = ".claude/worktrees"
DEFAULT_ACTIVE_MIN = 5
DEFAULT_STALE_MIN = 10
DEFAULT_RECENT_COUNT = 10
DEFAULT_HEARTBEAT_FIELDS = ("Phase", "Last action", "Next action", "Blockers", "Estimated")
DEFAULT_COMMIT_STATS = [
    ("stage-1", r"step .*\.1"),
    ("stage-2", r"step .*\.2"),
    ("review commits", r"plans/central/reviews"),
]


@dataclass
class Config:
    repo: Path
    heartbeat_dir: Path
    worktree_root: Path
    active_min: int
    stale_min: int
    recent_count: int
    state_file: Path
    update_state: bool = True
    commit_stats: list[tuple[str, str]] = field(default_factory=lambda: list(DEFAULT_COMMIT_STATS))
    heartbeat_fields: tuple[str, ...] = DEFAULT_HEARTBEAT_FIELDS


def default_state_file(repo: Path) -> Path:
    """Per-repo state path in /tmp, so concurrent repos don't overwrite each other."""
    digest = hashlib.sha1(str(repo.resolve()).encode()).hexdigest()[:10]
    return Path("/tmp") / f"agents_status_{digest}.txt"


def read_last_check(state_file: Path) -> datetime | None:
    try:
        ts = state_file.read_text().strip()
        return datetime.fromisoformat(ts)
    except (OSError, ValueError):
        return None


def write_last_check(state_file: Path, when: datetime) -> None:
    try:
        state_file.write_text(when.isoformat(timespec="seconds"))
    except OSError as e:
        print(f"  warning: could not write state file {state_file}: {e}", file=sys.stderr)


def human_delta(seconds: int) -> str:
    if seconds < 60:
        return f"{seconds}s"
    m, s = divmod(seconds, 60)
    if m < 60:
        return f"{m}m {s}s"
    h, m = divmod(m, 60)
    if h < 24:
        return f"{h}h {m}m"
    d, h = divmod(h, 24)
    return f"{d}d {h}h"


# --- Helpers -------------------------------------------------------------

def git(cfg: Config, *args: str) -> str:
    """Run a git command in the repo, return stdout stripped. Empty on error."""
    try:
        out = subprocess.run(
            ["git", *args],
            cwd=cfg.repo,
            capture_output=True,
            text=True,
            check=False,
        )
        return out.stdout.strip()
    except FileNotFoundError:
        return ""


def tag_for_age(age_min: int, cfg: Config) -> str:
    if age_min < cfg.active_min:
        return "active"
    if age_min < cfg.stale_min:
        return "stale"
    return "wedged"


def print_heartbeat(hb: Path, cfg: Config) -> str:
    """Print a heartbeat file header + filtered fields. Return its tag."""
    mtime = hb.stat().st_mtime
    age = int(time.time() - mtime)
    age_min, age_sec = divmod(age, 60)
    tag = tag_for_age(age_min, cfg)
    age_str = f"{age_min}m {age_sec}s old"
    print(f"  heartbeat: {Color.bold(hb.name)}  ({age_str}, {Color.tag(tag)})")
    field_re = re.compile(r"|".join(re.escape(f) for f in cfg.heartbeat_fields))
    try:
        lines = hb.read_text().splitlines()
    except OSError:
        return tag
    matched = [ln for ln in lines if field_re.search(ln)][:5]
    for ln in matched:
        print(f"    {Color.dim(ln)}")
    return tag


# --- Sections ------------------------------------------------------------

def section_time() -> None:
    print(Color.header("=== Time ==="))
    print(datetime.now().strftime("%a %b %d %H:%M:%S %Z %Y").strip())
    print()


def section_last_check(last_check: datetime | None, now: datetime, state_file: Path) -> None:
    print(Color.header("=== Last check ==="))
    if last_check is None:
        print(f"  {Color.dim(f'(no prior state — will write to {state_file} on exit)')}")
    else:
        delta = int((now - last_check).total_seconds())
        ago = Color.info(f"{human_delta(delta)} ago")
        print(f"  last ran: {last_check.isoformat(timespec='seconds')} ({ago})")
        print(f"  {Color.dim(f'state file: {state_file}')}")
    print()


def section_trunk_head(cfg: Config) -> None:
    print(Color.header("=== Trunk HEAD ==="))
    head = git(cfg, "log", "--oneline", "-1")
    if head:
        parts = head.split(" ", 1)
        if len(parts) == 2:
            print(f"{Color.sha(parts[0])} {parts[1]}")
        else:
            print(head)
    else:
        print(Color.bad("  (git command failed)"))
    print()


def section_recent_commits(cfg: Config, last_check: datetime | None) -> None:
    print(Color.header(f"=== Recent commits ({cfg.recent_count}) ==="))
    log_out = git(cfg, "log", "--oneline", f"-{cfg.recent_count}")
    for line in log_out.splitlines():
        parts = line.split(" ", 1)
        if len(parts) == 2:
            print(f"{Color.sha(parts[0])} {parts[1]}")
        else:
            print(line)

    stat_1h = len(git(cfg, "log", "--oneline", "--since=1 hour ago").splitlines())
    stat_24h = len(git(cfg, "log", "--oneline", "--since=24 hours ago").splitlines())
    stats = [f"{Color.bold(str(stat_1h))} in last hour", f"{Color.bold(str(stat_24h))} in last 24h"]
    for label, pattern in cfg.commit_stats:
        count = len(git(cfg, "log", "--oneline", f"--grep={pattern}").splitlines())
        stats.append(f"{Color.bold(str(count))} total {label}")
    sep = Color.dim(" · ")
    print(f"  {Color.bold('stats (absolute):')} {sep.join(stats)}")

    if last_check is not None:
        since_iso = last_check.isoformat(timespec="seconds")
        total_since = len(git(cfg, "log", "--oneline", f"--since={since_iso}").splitlines())
        diff_stats = [f"{Color.good(str(total_since))} new commits"]
        for label, pattern in cfg.commit_stats:
            count = len(git(cfg, "log", "--oneline", f"--since={since_iso}", f"--grep={pattern}").splitlines())
            count_str = Color.good(str(count)) if count > 0 else Color.dim(str(count))
            diff_stats.append(f"{count_str} new {label}")
        print(f"  {Color.bold('stats (since last check):')} {sep.join(diff_stats)}")
    else:
        print(f"  {Color.bold('stats (since last check):')} {Color.dim('first run — no prior state')}")
    print()


def section_worktrees(cfg: Config) -> list[tuple[str, int]]:
    """Print worktree list + stats. Return list of (worktree_name, ahead) tuples."""
    print(Color.header("=== Active worktrees ==="))
    list_out = git(cfg, "worktree", "list")
    print(list_out)
    wt_root = cfg.repo / cfg.worktree_root
    worktrees: list[tuple[str, int]] = []
    if wt_root.is_dir():
        for wt in sorted(wt_root.iterdir()):
            if not wt.is_dir():
                continue
            name = wt.name
            branch = f"worktree-{name}"
            ahead_out = git(cfg, "rev-list", "--count", f"trunk..{branch}")
            try:
                ahead = int(ahead_out) if ahead_out else 0
            except ValueError:
                ahead = 0
            worktrees.append((name, ahead))
    wt_locked = list_out.count("locked")
    wt_ahead = sum(1 for _, a in worktrees if a > 0)
    sep = Color.dim(" · ")
    print(
        f"  {Color.bold('stats:')} {Color.bold(str(len(worktrees)))} worktrees{sep}"
        f"{Color.bold(str(wt_locked))} locked{sep}"
        f"{Color.good(str(wt_ahead)) if wt_ahead > 0 else Color.dim('0')} ahead of trunk"
    )
    print()
    return worktrees


def section_main_heartbeats(cfg: Config) -> None:
    print(Color.header("=== Heartbeats (main repo) ==="))
    hb_dir = cfg.repo / cfg.heartbeat_dir
    triggered = 0
    tag_counts = {"active": 0, "stale": 0, "wedged": 0}
    completed = 0
    if hb_dir.is_dir():
        files = sorted(hb_dir.glob("*.md"))
        if not files:
            completed = 1
            print(f"  {Color.good('(heartbeat dir present but empty — last agent completed successfully)')}")
        else:
            for hb in files:
                triggered += 1
                tag = print_heartbeat(hb, cfg)
                tag_counts[tag] = tag_counts.get(tag, 0) + 1
    if triggered == 0 and completed == 0:
        print(f"  {Color.dim('(no main-repo agents running)')}")
    sep = Color.dim(" · ")
    print(
        f"  {Color.bold('stats:')} {Color.bold(str(triggered))} triggered{sep}"
        f"{Color.good(str(tag_counts['active']))} active{sep}"
        f"{Color.warn(str(tag_counts['stale']))} stale{sep}"
        f"{Color.bad(str(tag_counts['wedged']))} wedged{sep}"
        f"{Color.good(str(completed))} completed"
    )
    print()


def section_worktree_heartbeats(cfg: Config, worktrees: list[tuple[str, int]]) -> None:
    print(Color.header("=== Heartbeats per worktree ==="))
    tag_counts = {"active": 0, "stale": 0, "wedged": 0}
    with_hb = 0
    without_hb = 0
    completed = 0
    for name, ahead in worktrees:
        print()
        ahead_str = Color.good(f"ahead of trunk: {ahead}") if ahead > 0 else Color.dim(f"ahead of trunk: {ahead}")
        print(f"--- {Color.bold(name)} ({ahead_str}) ---")
        hb_dir = cfg.repo / cfg.worktree_root / name / cfg.heartbeat_dir
        found = False
        empty_dir = False
        if hb_dir.is_dir():
            files = sorted(hb_dir.glob("*.md"))
            if not files:
                empty_dir = True
            for hb in files:
                found = True
                tag = print_heartbeat(hb, cfg)
                tag_counts[tag] = tag_counts.get(tag, 0) + 1
        if found:
            with_hb += 1
        elif empty_dir and ahead > 0:
            completed += 1
            print(f"  {Color.good(f'(heartbeat deleted + {ahead} commits ahead — agent completed successfully)')}")
        else:
            without_hb += 1
            print(f"  {Color.dim('(no heartbeat — agent may be starting or dead)')}")
    print()
    sep = Color.dim(" · ")
    print(
        f"  {Color.bold('stats:')} {Color.bold(str(with_hb))} with heartbeat{sep}"
        f"{Color.bold(str(without_hb))} without{sep}"
        f"{Color.good(str(tag_counts['active']))} active{sep}"
        f"{Color.warn(str(tag_counts['stale']))} stale{sep}"
        f"{Color.bad(str(tag_counts['wedged']))} wedged{sep}"
        f"{Color.good(str(completed))} completed"
    )
    print()


def section_heuristic(cfg: Config) -> None:
    print(Color.header("=== Wedged-agent heuristic ==="))
    print(f"  {Color.good('Alive:')}  heartbeat < {cfg.active_min} min old AND phase changing")
    print(f"  {Color.warn('Stuck:')}  heartbeat > {cfg.stale_min} min old OR phase same for 3+ checks")
    print(f"  {Color.bad('Dead:')}   worktree vanished without commit")


# --- Main ----------------------------------------------------------------

def parse_args(argv: list[str]) -> Config:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--repo", type=Path, default=Path.cwd(), help="Repo root (default: cwd)")
    p.add_argument("--heartbeat-dir", default=DEFAULT_HEARTBEAT_DIR,
                   help=f"Heartbeat dir relative to repo and worktrees (default: {DEFAULT_HEARTBEAT_DIR})")
    p.add_argument("--worktree-root", default=DEFAULT_WORKTREE_ROOT,
                   help=f"Worktree root relative to repo (default: {DEFAULT_WORKTREE_ROOT})")
    p.add_argument("--active-min", type=int, default=DEFAULT_ACTIVE_MIN,
                   help=f"Active threshold in minutes (default: {DEFAULT_ACTIVE_MIN})")
    p.add_argument("--stale-min", type=int, default=DEFAULT_STALE_MIN,
                   help=f"Stale threshold in minutes (default: {DEFAULT_STALE_MIN})")
    p.add_argument("--recent", type=int, default=DEFAULT_RECENT_COUNT,
                   help=f"Recent commits to show (default: {DEFAULT_RECENT_COUNT})")
    p.add_argument("--commit-stat", action="append", default=[], metavar="LABEL=PATTERN",
                   help="Add a commit-stat grep pattern (repeatable). Replaces defaults if any given.")
    p.add_argument("--state-file", type=Path, default=None,
                   help="Where to persist last-check timestamp (default: /tmp/agents_status_<repo-hash>.txt)")
    p.add_argument("--no-update-state", action="store_true",
                   help="Read last-check but do not overwrite the state file")
    p.add_argument("--no-color", action="store_true",
                   help="Disable ANSI colors (also honored via NO_COLOR env var)")
    p.add_argument("--force-color", action="store_true",
                   help="Force ANSI colors even when stdout isn't a TTY")
    args = p.parse_args(argv)

    commit_stats = list(DEFAULT_COMMIT_STATS)
    if args.commit_stat:
        commit_stats = []
        for spec in args.commit_stat:
            if "=" not in spec:
                p.error(f"--commit-stat must be LABEL=PATTERN, got: {spec}")
            label, pattern = spec.split("=", 1)
            commit_stats.append((label, pattern))

    if args.force_color:
        Color.enabled = True
    else:
        Color.configure(force_off=args.no_color)

    repo_resolved = args.repo.resolve()
    state_file = args.state_file if args.state_file else default_state_file(repo_resolved)
    return Config(
        repo=repo_resolved,
        heartbeat_dir=Path(args.heartbeat_dir),
        worktree_root=Path(args.worktree_root),
        active_min=args.active_min,
        stale_min=args.stale_min,
        recent_count=args.recent,
        state_file=state_file,
        update_state=not args.no_update_state,
        commit_stats=commit_stats,
    )


def main(argv: list[str] | None = None) -> int:
    cfg = parse_args(argv if argv is not None else sys.argv[1:])
    if not (cfg.repo / ".git").exists():
        print(f"error: not a git repo: {cfg.repo}", file=sys.stderr)
        return 1
    now = datetime.now()
    last_check = read_last_check(cfg.state_file)
    section_time()
    section_last_check(last_check, now, cfg.state_file)
    section_trunk_head(cfg)
    section_recent_commits(cfg, last_check)
    worktrees = section_worktrees(cfg)
    section_main_heartbeats(cfg)
    section_worktree_heartbeats(cfg, worktrees)
    section_heuristic(cfg)
    if cfg.update_state:
        write_last_check(cfg.state_file, now)
    return 0


if __name__ == "__main__":
    sys.exit(main())
