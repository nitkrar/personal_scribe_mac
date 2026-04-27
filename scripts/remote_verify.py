#!/usr/bin/env python3
"""Push current branch, pull on remote, verify HEAD parity, build, test.

Defaults match the secondary Mac at Nitins-MacBook-Air.local. Override with
--host / --path for other targets.

Exits non-zero on the first failed step.
"""
import argparse
import shlex
import subprocess
import sys

DEFAULT_HOST = "nitinkumar@Nitins-MacBook-Air.local"
DEFAULT_PATH = "/Users/nitinkumar/Projects/nitkrar/personal_scribe"


def run(cmd, *, capture=False):
    """Run a command locally. Streams output unless capture=True."""
    if capture:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return result.stdout.strip()
    subprocess.run(cmd, check=True)


def ssh(host, remote_cmd, *, capture=False):
    """Run a single shell command on the remote host via ssh."""
    return run(["ssh", host, remote_cmd], capture=capture)


def step(label):
    print(f"\n=== {label} ===", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default=DEFAULT_HOST, help="ssh target")
    parser.add_argument("--path", default=DEFAULT_PATH, help="remote repo path")
    parser.add_argument(
        "--no-test", action="store_true", help="skip the swift test step"
    )
    parser.add_argument(
        "--no-package",
        action="store_true",
        help="skip the scripts/package.py -ir -c release step",
    )
    args = parser.parse_args()

    quoted_path = shlex.quote(args.path)

    step("git push")
    run(["git", "push"])

    local_head = run(["git", "rev-parse", "HEAD"], capture=True)
    print(f"local HEAD : {local_head}")

    step("remote pull")
    ssh(args.host, f"cd {quoted_path} && git fetch && git pull --ff-only")

    step("validate HEAD parity")
    remote_head = ssh(
        args.host, f"cd {quoted_path} && git rev-parse HEAD", capture=True
    )
    print(f"remote HEAD: {remote_head}")
    if remote_head != local_head:
        print(
            f"ERROR: HEAD mismatch (local {local_head} vs remote {remote_head})",
            file=sys.stderr,
        )
        sys.exit(1)
    print("HEAD parity OK")

    step("swift build")
    ssh(args.host, f"cd {quoted_path} && swift build")

    if not args.no_test:
        step("swift test")
        ssh(args.host, f"cd {quoted_path} && swift test")

    if not args.no_package:
        step("package.py -ir -c release")
        ssh(args.host, f"cd {quoted_path} && scripts/package.py -ir -c release")

    print("\nAll steps passed.")


if __name__ == "__main__":
    main()
