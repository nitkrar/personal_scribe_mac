#!/usr/bin/env python3
"""
package.py — build Ninimma.app; optionally install to /Applications,
produce a DMG, and launch.

Replaces the earlier package.sh. Shell logic had grown to ~370 lines
of option parsing + conditional blocks + path juggling; Python is a
cleaner fit.

Notes:
  * Always rebuilds the .app fresh — no way to skip. Avoids running a
    stale binary after a code change.
  * Ad-hoc / self-signed with hardened runtime + audio-input
    entitlement.
  * Install replaces /Applications/Ninimma.app at a stable path —
    per-path TCC grants (Mic, Input Monitoring, Accessibility)
    persist across rebuilds.
  * First-run Gatekeeper: right-click Ninimma.app → Open, OR
      xattr -dr com.apple.quarantine /Applications/Ninimma.app
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# --- Constants ---------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parent.parent
APP_NAME = "Ninimma"
BINARY_NAME = "PersonalScribeAppKit"
BUNDLE_ID = "com.nitkrar.personal_scribe"
VERSION = "0.1.0"
MIN_MACOS = "14.0"
APP_PATH = REPO_ROOT / f"{APP_NAME}.app"
INSTALL_PATH = Path(f"/Applications/{APP_NAME}.app")
ICNS_SOURCE = (
    REPO_ROOT / "Sources" / "PersonalScribeAppKit" / "Resources" / "AppIcon.icns"
)
SUPPORT_DIR = Path.home() / "Library" / "Application Support" / "personal_scribe"
RUNTIME_FRAMEWORK_NAME = "whisper.framework"
RUNTIME_FRAMEWORK_RPATH = "@loader_path/../Frameworks"

# Keep Stable self-signed identity for TCC persistence across rebuilds
# (see sign() for why).
SIGN_IDENTITY_PREFERRED = "Nitkrar Dev"


# --- Subprocess helpers ------------------------------------------------------


def run(
    cmd: list[str],
    *,
    check: bool = True,
    capture: bool = False,
    quiet: bool = False,
) -> subprocess.CompletedProcess:
    kwargs: dict = {}
    if capture:
        kwargs["capture_output"] = True
        kwargs["text"] = True
    elif quiet:
        kwargs["stdout"] = subprocess.DEVNULL
        kwargs["stderr"] = subprocess.DEVNULL
    return subprocess.run(cmd, check=check, **kwargs)


def run_ignore(cmd: list[str]) -> None:
    """Best-effort call — ignore non-zero exit + missing binaries."""
    try:
        subprocess.run(
            cmd, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
    except FileNotFoundError:
        pass


def git_sha() -> str:
    result = subprocess.run(
        ["git", "-C", str(REPO_ROOT), "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
        check=False,
    )
    sha = result.stdout.strip()
    return sha if sha else "unknown"


def binary_has_rpath(binary: Path, rpath: str) -> bool:
    result = run(["otool", "-l", str(binary)], capture=True)
    return f"path {rpath} (offset " in (result.stdout or "")


# --- CLI ---------------------------------------------------------------------


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="package.py",
        description="Build Ninimma.app; optionally install/DMG/launch.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  scripts/package.py                         # build ./Ninimma.app only\n"
            "  scripts/package.py -ir                     # build + install + launch\n"
            "  scripts/package.py -c release -ir          # release build + install + launch\n"
            "  scripts/package.py -d                      # build + DMG (for GitHub Release)\n"
            "  scripts/package.py --reset -ir             # fresh-install dry run (keeps models)\n"
            "  scripts/package.py --reset -m -ir          # full wipe including models\n"
            "  scripts/package.py --reset -y              # wipe (keep models), no build\n"
        ),
    )
    parser.add_argument(
        "-c",
        "--config",
        choices=["debug", "release"],
        default="debug",
        help="Build config (default: debug)",
    )
    parser.add_argument(
        "-i",
        "--install",
        action="store_true",
        help="Replace /Applications/Ninimma.app after build",
    )
    parser.add_argument(
        "-d",
        "--dmg",
        action="store_true",
        help=f"Also emit {APP_NAME}-<ver>.dmg at repo root",
    )
    parser.add_argument(
        "-r",
        "--run",
        action="store_true",
        help="Launch after install (implies --install)",
    )
    parser.add_argument(
        "--reset",
        action="store_true",
        help=(
            "Simulate fresh install: quit running app, delete the installed "
            ".app, wipe ~/Library/.../personal_scribe/ (recordings + "
            "transcripts; models kept unless --delete-models also passed), "
            "delete UserDefaults, reset TCC grants, clear .build/. Runs "
            "BEFORE the build step. DESTRUCTIVE — prompts unless -y."
        ),
    )
    parser.add_argument(
        "-m",
        "--delete-models",
        action="store_true",
        help=(
            "When combined with --reset, also wipe "
            "~/Library/.../personal_scribe/models/. Default: preserve models "
            "(slow to re-download; unrelated to most fresh-install tests)."
        ),
    )
    parser.add_argument(
        "-y",
        "--yes",
        action="store_true",
        help="Skip --reset confirmation prompt",
    )
    args = parser.parse_args(argv)
    # -r implies -i (mirror the shell script's behavior)
    if args.run:
        args.install = True
    return args


# --- Reset -------------------------------------------------------------------


def quit_running_app() -> None:
    run_ignore(["osascript", "-e", f'tell application "{APP_NAME}" to quit'])
    run_ignore(["pkill", "-f", BINARY_NAME])


def do_reset(args: argparse.Namespace) -> None:
    """Wipe everything the app owns on this machine. DESTRUCTIVE."""
    data_note = (
        f"{SUPPORT_DIR} (including models/)"
        if args.delete_models
        else f"{SUPPORT_DIR} (preserving models/)"
    )
    print("==> --reset: fresh-install simulation")
    print("    Will remove:")
    print(f"      • installed app:    {INSTALL_PATH}")
    print(f"      • user data:        {data_note}")
    print(f"      • UserDefaults:     {BUNDLE_ID}")
    print(
        f"      • TCC grants:       Microphone, ListenEvent, Accessibility ({BUNDLE_ID})"
    )
    print(f"      • build artifacts:  {REPO_ROOT / '.build'}")
    print(f"      • local .app:       {APP_PATH}")
    if not args.yes:
        answer = input("    Proceed? [y/N] ").strip().lower()
        if answer not in {"y", "yes"}:
            print("    aborted")
            sys.exit(1)

    print("    [1/5] quit running app")
    quit_running_app()

    print("    [2/5] remove installed .app + local .app + .build/")
    for path in (INSTALL_PATH, APP_PATH, REPO_ROOT / ".build"):
        if path.exists():
            shutil.rmtree(path, ignore_errors=True)

    if args.delete_models:
        print(f"    [3/5] wipe {SUPPORT_DIR} (including models/)")
        if SUPPORT_DIR.exists():
            shutil.rmtree(SUPPORT_DIR, ignore_errors=True)
    elif SUPPORT_DIR.exists():
        print(f"    [3/5] wipe {SUPPORT_DIR} contents except models/")
        # Delete every child of SUPPORT_DIR except `models/`. Keeps
        # the downloaded voice models so the next launch doesn't
        # re-download hundreds of MB.
        for child in SUPPORT_DIR.iterdir():
            if child.name == "models":
                continue
            if child.is_dir():
                shutil.rmtree(child, ignore_errors=True)
            else:
                child.unlink(missing_ok=True)
    else:
        print("    [3/5] (no support dir to wipe)")

    # UserDefaults triple-tap. `defaults delete` alone isn't
    # reliable on modern macOS — cfprefsd caches values in memory and
    # can rewrite the plist from cache on the next read. Belt + two
    # suspenders: delete via CLI, remove the plist files directly,
    # then killall cfprefsd to force a reload. Without the daemon
    # reload, the next app launch reads stale values (e.g.
    # OnboardingCompleted=true survives and the first-run Permissions
    # auto-open never fires → no mic TCC prompt).
    print(f"    [4/5] flush UserDefaults for {BUNDLE_ID}")
    run_ignore(["defaults", "delete", BUNDLE_ID])
    prefs_dir = Path.home() / "Library" / "Preferences"
    for plist in prefs_dir.glob(f"{BUNDLE_ID}.plist*"):
        plist.unlink(missing_ok=True)
    run_ignore(["killall", "cfprefsd"])

    print(f"    [5/5] reset TCC grants for {BUNDLE_ID}")
    for service in ("Microphone", "ListenEvent", "Accessibility"):
        run_ignore(["tccutil", "reset", service, BUNDLE_ID])

    print("    reset complete")


# --- Build -------------------------------------------------------------------


def build(config: str) -> Path:
    """Run swift build and return the executable path."""
    print(f"==> Building {BINARY_NAME} ({config})...")
    run(["swift", "build", "-c", config, "--product", BINARY_NAME])
    binary = REPO_ROOT / ".build" / config / BINARY_NAME
    if not binary.is_file() or not os.access(binary, os.X_OK):
        print(f"error: expected executable at {binary} not found", file=sys.stderr)
        sys.exit(1)
    return binary


# --- .app assembly -----------------------------------------------------------


def info_plist_contents() -> str:
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>{APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>{BINARY_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>{APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>{BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>{APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>{VERSION}</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleVersion</key>
    <string>{VERSION}</string>
    <key>PersonalScribeGitSHA</key>
    <string>{git_sha()}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>{MIN_MACOS}</string>
    <!-- No LSUIElement: the app launches as a regular (Dock-visible)
         process. Users who want a menu-bar-only setup enable
         "Background mode" in Settings → General → Application; the
         app reads that preference in `PersonalScribeAppMain` at startup
         and calls `NSApp.setActivationPolicy(.accessory)` to hide
         from the Dock / Cmd+Tab / Force Quit. Changes only take
         effect on relaunch. -->
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Nitkrar. MIT License.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Ninimma transcribes your speech into text locally on your Mac. Audio never leaves your device.</string>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
"""


def assemble_app(binary: Path, config: str) -> None:
    print(f"==> Assembling {APP_PATH}...")
    if APP_PATH.exists():
        shutil.rmtree(APP_PATH)
    (APP_PATH / "Contents" / "MacOS").mkdir(parents=True)
    (APP_PATH / "Contents" / "Frameworks").mkdir(parents=True)
    (APP_PATH / "Contents" / "Resources").mkdir(parents=True)

    dest_binary = APP_PATH / "Contents" / "MacOS" / BINARY_NAME
    shutil.copy2(binary, dest_binary)

    # Strip symbol tables on release builds. Statically linked
    # FluidAudio + GRDB drop ~187k symbols + a 4.4MB string table
    # into LC_SYMTAB that the linker doesn't remove; unstripped
    # release binaries are ~14MB, stripped ~8MB. Debug keeps symbols
    # for crash symbolication.
    if config == "release":
        print("==> Stripping release binary symbols...")
        run(["strip", "-x", str(dest_binary)])

    framework_source = binary.resolve().parent / RUNTIME_FRAMEWORK_NAME
    framework_dest = APP_PATH / "Contents" / "Frameworks" / RUNTIME_FRAMEWORK_NAME
    print(f"==> Bundling {RUNTIME_FRAMEWORK_NAME} from {framework_source}...")
    if not framework_source.is_dir():
        print(
            f"error: runtime framework not found at {framework_source}",
            file=sys.stderr,
        )
        sys.exit(1)
    shutil.copytree(framework_source, framework_dest, symlinks=True)

    if not binary_has_rpath(dest_binary, RUNTIME_FRAMEWORK_RPATH):
        print(f"==> Adding runtime search path {RUNTIME_FRAMEWORK_RPATH}...")
        run(
            [
                "install_name_tool",
                "-add_rpath",
                RUNTIME_FRAMEWORK_RPATH,
                str(dest_binary),
            ]
        )

    (APP_PATH / "Contents" / "Info.plist").write_text(info_plist_contents())
    (APP_PATH / "Contents" / "PkgInfo").write_text("APPL????")

    # The canonical .icns is a checked-in artifact
    # (Sources/PersonalScribeAppKit/Resources/AppIcon.icns) with
    # proper RGBA transparency. Earlier revisions auto-generated from
    # logo_dark.png via sips+iconutil, but that source is RGB-only
    # with no alpha — result rendered as a flat dark square. Ship
    # the hand-authored icns.
    print(f"==> Embedding {ICNS_SOURCE} as app icon...")
    if not ICNS_SOURCE.is_file():
        print(f"error: app icon source not found at {ICNS_SOURCE}", file=sys.stderr)
        sys.exit(1)
    shutil.copy2(
        ICNS_SOURCE, APP_PATH / "Contents" / "Resources" / f"{APP_NAME}.icns"
    )


# --- Signing -----------------------------------------------------------------


def resolve_signing_identity() -> str:
    """
    Prefer the stable self-signed identity (`Nitkrar Dev`) if present.
    Stable identity → TCC permissions persist across rebuilds because
    TCC keys signed apps on signing identity, not on CD hash. Ad-hoc
    (`-`) is the fallback for fresh clones / other machines.

    Use `security find-identity -p codesigning` WITHOUT `-v`.
    Self-signed roots report CSSMERR_TP_NOT_TRUSTED and get filtered
    by `-v` (valid-only), but `codesign --sign` uses them fine — it
    doesn't require a trust chain for local signing.
    """
    result = subprocess.run(
        ["security", "find-identity", "-p", "codesigning"],
        capture_output=True,
        text=True,
        check=False,
    )
    if f'"{SIGN_IDENTITY_PREFERRED}"' in (result.stdout or ""):
        return SIGN_IDENTITY_PREFERRED
    print(
        f"==> '{SIGN_IDENTITY_PREFERRED}' codesigning identity not found — "
        "falling back to ad-hoc."
    )
    print(
        "    (Permissions will reset each rebuild. Create the cert in "
        "Keychain Access to preserve TCC grants across rebuilds on this "
        "machine.)"
    )
    return "-"


ENTITLEMENTS_PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
"""


def sign() -> None:
    identity = resolve_signing_identity()
    frameworks_dir = APP_PATH / "Contents" / "Frameworks"
    for framework in sorted(frameworks_dir.glob("*.framework")):
        print(f"==> Signing bundled framework {framework.name} with identity: {identity}")
        run(
            [
                "codesign",
                "--force",
                "--sign",
                identity,
                "--timestamp=none",
                str(framework),
            ]
        )
        run(["codesign", "--verify", "--verbose", str(framework)])

    print(
        f"==> Signing with identity: {identity} "
        "(hardened runtime + mic entitlement)..."
    )
    with tempfile.NamedTemporaryFile(
        prefix="personal_scribe-entitlements.",
        suffix=".plist",
        mode="w",
        delete=False,
    ) as f:
        f.write(ENTITLEMENTS_PLIST)
        ent_path = f.name
    try:
        # `quiet=True` previously hid codesign's stderr — the real error
        # message went to /dev/null and we just saw "command failed". Let
        # codesign's stdout/stderr through so failures surface in-band.
        run(
            [
                "codesign",
                "--force",
                "--sign",
                identity,
                "--deep",
                "--options",
                "runtime",
                "--entitlements",
                ent_path,
                "--timestamp=none",
                str(APP_PATH),
            ],
        )
        run(["codesign", "--verify", "--verbose", str(APP_PATH)])
    finally:
        Path(ent_path).unlink(missing_ok=True)


# --- DMG ---------------------------------------------------------------------


def make_dmg() -> Path:
    print()
    print("==> Packaging DMG...")
    dmg_path = REPO_ROOT / f"{APP_NAME}-{VERSION}.dmg"
    if dmg_path.exists():
        dmg_path.unlink()
    with tempfile.TemporaryDirectory(prefix="personal_scribe-dmg-staging") as staging:
        staging_dir = Path(staging)
        shutil.copytree(APP_PATH, staging_dir / f"{APP_NAME}.app", symlinks=True)
        (staging_dir / "Applications").symlink_to("/Applications")
        run(
            [
                "hdiutil",
                "create",
                "-volname",
                f"{APP_NAME} {VERSION}",
                "-srcfolder",
                str(staging_dir),
                "-ov",
                "-format",
                "UDZO",
                "-fs",
                "HFS+",
                str(dmg_path),
            ],
            quiet=True,
        )
    run(["hdiutil", "verify", str(dmg_path)], quiet=True)
    size = subprocess.check_output(["du", "-sh", str(dmg_path)], text=True).split()[0]
    print(f"✓ Built {dmg_path} ({size})")
    return dmg_path


# --- Install / Run -----------------------------------------------------------


def install() -> None:
    print()
    print(f"==> Installing to {INSTALL_PATH}...")
    run_ignore(["osascript", "-e", f'tell application "{APP_NAME}" to quit'])
    # Brief pause so the app has time to release file handles before
    # ditto tries to overwrite.
    import time

    time.sleep(1)
    if INSTALL_PATH.exists():
        shutil.rmtree(INSTALL_PATH)
    run(["ditto", str(APP_PATH), str(INSTALL_PATH)])
    print(f"✓ Installed {INSTALL_PATH}")


def launch() -> None:
    print()
    print(f"==> Launching {INSTALL_PATH}...")
    run(["open", str(INSTALL_PATH)])


# --- Main --------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    if args.reset:
        do_reset(args)

    binary = build(args.config)
    assemble_app(binary, args.config)
    sign()

    size = subprocess.check_output(["du", "-sh", str(APP_PATH)], text=True).split()[0]
    print(f"✓ Built {APP_PATH} ({size})")

    dmg_path: Path | None = None
    if args.dmg:
        dmg_path = make_dmg()

    if args.install:
        install()

    if args.run:
        launch()

    print()
    if not args.install and not args.dmg:
        print(f'  Launch:  open "{APP_PATH}"')
    elif args.dmg and not args.install and dmg_path is not None:
        print(
            f'  Install: open "{dmg_path}" → drag {APP_NAME}.app into Applications'
        )
    print()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except subprocess.CalledProcessError as exc:
        print(f"error: command failed: {exc.cmd}", file=sys.stderr)
        sys.exit(exc.returncode or 1)
    except KeyboardInterrupt:
        print("", file=sys.stderr)
        sys.exit(130)
