#!/usr/bin/env python3
"""
SahilStats Agent — Zero-intervention development workflow.

The agent handles the complete loop autonomously:
  1. Read and edit Swift files
  2. Commit and push to GitHub
  3. Pull on personal Mac
  4. Build — if errors/warnings appear, read the affected files, fix them,
     commit, and rebuild. Repeat until clean.
  5. Deploy to iPhone (ios-deploy)
  6. Deploy to Apple Watch Series 8 (xcrun devicectl) — separately, not
     relying on auto-sync which is unreliable.

No per-command approval. User describes a task; agent does everything.

Usage:
  python3 sahil_agent.py                    # interactive
  python3 sahil_agent.py "fix X and deploy" # single-shot
"""

import json
import os
import subprocess
import sys
from pathlib import Path

import truststore
truststore.inject_into_ssl()
import anthropic

# ── Config ────────────────────────────────────────────────────────────────────

REPO         = Path.home() / "personal/SahilStatsLite"
PERSONAL_MAC = "narayan@Narayans-MacBook-Pro.local"
REMOTE_REPO  = "/Users/narayan/SahilStats/SahilStatsLite/SahilStatsLite"
BUILD_DIR    = "/tmp/SahilStatsBuild"
IOS_DEPLOY   = "/opt/homebrew/bin/ios-deploy"
IPHONE_UDID  = "00008140-000078682693001C"   # ios-deploy UDID
WATCH_DC     = "Narayans-AppleWatch-8.coredevice.local"  # Watch Series 8 — Bonjour hostname works, UUID doesn't
MODEL        = "claude-sonnet-4-6"

XCODEBUILD = f"""
xcodebuild \\
  -scheme SahilStatsLite \\
  -configuration Debug \\
  -destination 'id={IPHONE_UDID}' \\
  -derivedDataPath {BUILD_DIR} \\
  -allowProvisioningUpdates \\
  DEVELOPMENT_TEAM=TTV9QQRD5H \\
  CODE_SIGN_STYLE=Automatic \\
  2>&1 | grep -E '^.*error:|Build succeeded|Build FAILED' | grep -v SourcePackages | head -50
"""

# ── Load context ───────────────────────────────────────────────────────────────

def load_context() -> str:
    parts = []
    for fname in ["claude.md", "HANDOFF.md"]:
        p = REPO / fname
        if p.exists():
            parts.append(f"--- {fname} ---\n{p.read_text()}")
    return "\n\n".join(parts)

# ── Helpers ────────────────────────────────────────────────────────────────────

def _local(cmd: str, cwd=None) -> str:
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True, cwd=cwd or str(REPO))
    out = r.stdout.strip()
    err = r.stderr.strip()
    return (out + ("\n" + err if err else "")).strip() or "(no output)"

def _ssh(cmd: str, timeout=300) -> str:
    r = subprocess.run(["ssh", PERSONAL_MAC, cmd],
                       capture_output=True, text=True, timeout=timeout)
    out = r.stdout.strip()
    err = r.stderr.strip()
    return (out + ("\n" + err if err else "")).strip() or "(no output)"

def _ssh_script(script: str, timeout=600) -> str:
    r = subprocess.run(["ssh", PERSONAL_MAC, "bash", "-s"],
                       input=script, capture_output=True, text=True, timeout=timeout)
    out = r.stdout.strip()
    err = r.stderr.strip()
    return (out + ("\n" + err if err else "")).strip() or "(no output)"

# ── Tools ─────────────────────────────────────────────────────────────────────

def read_file(path: str) -> str:
    f = REPO / path
    return f.read_text() if f.exists() else f"ERROR: {path} not found"

def write_file(path: str, content: str) -> str:
    f = REPO / path
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(content)
    return f"Written: {path}"

def list_files(directory: str = "") -> str:
    target = REPO / directory if directory else REPO
    if not target.exists():
        return f"ERROR: {directory} not found"
    files = sorted(
        str(f.relative_to(REPO))
        for f in target.rglob("*")
        if f.is_file() and ".git" not in f.parts and ".DS_Store" not in str(f)
    )
    return "\n".join(files)

def run_local(command: str) -> str:
    return _local(command)

def git_commit_and_push(files: list[str], message: str) -> str:
    results = []
    for f in files:
        r = _local(f"git add {f}")
        results.append(f"staged: {f}")
    msg = f"{message}\n\nCo-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>"
    commit = _local(f'git commit -m {json.dumps(msg)}')
    push = _local("git push origin main")
    return "\n".join(results + [commit, push])

def build() -> str:
    """Pull latest on personal Mac and build. Returns full error/warning output."""
    script = f"""
set -e
cd {REMOTE_REPO}
git pull origin main 2>&1 | tail -2
echo '--- BUILD START ---'
{XCODEBUILD}
echo '--- BUILD END ---'
"""
    result = _ssh_script(script)
    return result

def deploy_iphone() -> str:
    """Install the built app on Narayan's iPhone via ios-deploy."""
    script = f"""
APP=$(find {BUILD_DIR} -name "SahilStatsLite.app" -not -path "*/watchos*" -not -path "*Watch*" | head -1)
if [ -z "$APP" ]; then echo "ERROR: iPhone app not found. Run build first."; exit 1; fi
echo "Installing: $APP"
{IOS_DEPLOY} --id {IPHONE_UDID} --bundle "$APP" --justlaunch
echo "iPhone: installed and launched"
"""
    return _ssh(f"bash -s << 'EOF'\n{script}\nEOF")

def deploy_watch() -> str:
    """Install the Watch app on Apple Watch Series 8 (the remote scoring watch) via xcrun devicectl."""
    script = f"""
WATCH=$(find {BUILD_DIR} -name "SahilStatsLiteWatch Watch App.app" -path "*/watchos*" | head -1)
if [ -z "$WATCH" ]; then echo "ERROR: Watch app not found. Run build first."; exit 1; fi
BUILD_VER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$WATCH/Info.plist" 2>/dev/null || echo "?")
echo "Installing Watch v$BUILD_VER: $WATCH"
xcrun devicectl device install app --device {WATCH_DC} "$WATCH" 2>&1 | tail -5
echo "$BUILD_VER" > /tmp/_sahil_last_watch_deploy.txt
echo "Watch Series 8 (scoring remote): installed v$BUILD_VER"
"""
    return _ssh(f"bash -s << 'EOF'\n{script}\nEOF")

def deploy_all() -> str:
    """Pull, build, deploy to iPhone, deploy to Watch Series 8 — all in one."""
    return _ssh(f"bash /Users/narayan/SahilStats/deploy.sh")

def check_devices() -> str:
    """Check which devices are reachable (iPhone + Watch)."""
    return _ssh("xcrun devicectl list devices 2>&1 | grep -E 'iPhone|Watch|iPad'")

def check_sync() -> str:
    """
    Verify iPhone and Watch are running the same build as the last deploy.

    - iPhone: queried directly via xcrun devicectl (bundleVersion).
    - Watch: xcrun devicectl cannot enumerate watchOS apps; sync is inferred
      from whether the last deploy.sh succeeded (both deploy atomically).
    - Build artifact: reads CFBundleVersion from /tmp/SahilStatsBuild Info.plist.
    """
    script = r"""
set -e

IPHONE_DC="E52AFF08-9E71-52C0-8608-A9A529C5205C"
BUILD_DIR="/tmp/SahilStatsBuild"
BUNDLE_ID="com.narayan.SahilStats"

# 1. Last built artifact version
ARTIFACT_APP=$(find "$BUILD_DIR" -name "SahilStatsLite.app" -not -path "*watchos*" -not -path "*Watch*" 2>/dev/null | head -1)
if [ -n "$ARTIFACT_APP" ]; then
  ARTIFACT_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ARTIFACT_APP/Info.plist" 2>/dev/null || echo "?")
  ARTIFACT_DATE=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$ARTIFACT_APP")
  echo "Last build artifact : v$ARTIFACT_BUILD  (built $ARTIFACT_DATE)"
else
  ARTIFACT_BUILD="none"
  echo "Last build artifact : none found in $BUILD_DIR — run deploy first"
fi

# 2. iPhone installed version
xcrun devicectl device info apps \
  --device "$IPHONE_DC" \
  --include-removable-apps \
  --json-output /tmp/_sahil_sync_iphone.json 2>/dev/null
IPHONE_BUILD=$(python3 -c "
import json, sys
data = json.load(open('/tmp/_sahil_sync_iphone.json'))
apps = data.get('result', {}).get('apps', [])
app = next((a for a in apps if '$BUNDLE_ID' in str(a.get('bundleIdentifier',''))), None)
print(app['bundleVersion'] if app else 'not_installed')
" 2>/dev/null || echo "error")

if [ "$IPHONE_BUILD" = "not_installed" ]; then
  echo "iPhone              : not installed"
elif [ "$IPHONE_BUILD" = "error" ]; then
  echo "iPhone              : could not query (device may be locked)"
elif [ "$IPHONE_BUILD" = "$ARTIFACT_BUILD" ]; then
  echo "iPhone              : ✅  v$IPHONE_BUILD  (matches last build)"
else
  echo "iPhone              : ⚠️   v$IPHONE_BUILD  (last build is v$ARTIFACT_BUILD — deploy needed)"
fi

# 3. Watch — infer from last deploy log
WATCH_LOG="/tmp/_sahil_last_watch_deploy.txt"
if [ -f "$WATCH_LOG" ]; then
  WATCH_BUILD=$(cat "$WATCH_LOG")
  if [ "$WATCH_BUILD" = "$ARTIFACT_BUILD" ]; then
    echo "Watch Series 8      : ✅  v$WATCH_BUILD  (deployed from same build as iPhone)"
  else
    echo "Watch Series 8      : ⚠️   v$WATCH_BUILD  (last build is v$ARTIFACT_BUILD — deploy needed)"
  fi
else
  echo "Watch Series 8      : unknown  (no deploy log yet — run deploy to establish baseline)"
fi
"""
    return _ssh_script(script)

def ssh_run(command: str) -> str:
    """Run an arbitrary command on the personal Mac."""
    return _ssh(command)

# ── Tool definitions ───────────────────────────────────────────────────────────

TOOLS = [
    {
        "name": "read_file",
        "description": "Read a Swift file. Always read before editing.",
        "input_schema": {
            "type": "object",
            "properties": {"path": {"type": "string"}},
            "required": ["path"]
        }
    },
    {
        "name": "write_file",
        "description": "Write or overwrite a file with complete content.",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string"},
                "content": {"type": "string"}
            },
            "required": ["path", "content"]
        }
    },
    {
        "name": "list_files",
        "description": "List files in the repo or a subdirectory.",
        "input_schema": {
            "type": "object",
            "properties": {"directory": {"type": "string"}}
        }
    },
    {
        "name": "run_local",
        "description": "Run a shell command on the work Mac (git status, diff, log, etc.)",
        "input_schema": {
            "type": "object",
            "properties": {"command": {"type": "string"}},
            "required": ["command"]
        }
    },
    {
        "name": "git_commit_and_push",
        "description": "Stage files, commit, and push to GitHub.",
        "input_schema": {
            "type": "object",
            "properties": {
                "files": {"type": "array", "items": {"type": "string"}},
                "message": {"type": "string"}
            },
            "required": ["files", "message"]
        }
    },
    {
        "name": "build",
        "description": (
            "Pull latest on personal Mac and build for device. "
            "Returns all errors and warnings. "
            "If errors exist: read the affected files, fix them with write_file, "
            "commit with git_commit_and_push, then call build again. "
            "Repeat until 'Build succeeded' appears with no errors."
        ),
        "input_schema": {"type": "object", "properties": {}}
    },
    {
        "name": "deploy_iphone",
        "description": "Install the built app on Narayan's iPhone via ios-deploy. Call build first.",
        "input_schema": {"type": "object", "properties": {}}
    },
    {
        "name": "deploy_watch",
        "description": (
            "Install the Watch app on Apple Watch Series 8 via xcrun devicectl. "
            "This deploys directly — no waiting for auto-sync. Call build first."
        ),
        "input_schema": {"type": "object", "properties": {}}
    },
    {
        "name": "deploy_all",
        "description": "Convenience: pull + build + deploy iPhone + deploy Watch in one step.",
        "input_schema": {"type": "object", "properties": {}}
    },
    {
        "name": "check_devices",
        "description": "Check which devices are reachable (iPhone, Watch).",
        "input_schema": {"type": "object", "properties": {}}
    },
    {
        "name": "check_sync",
        "description": (
            "Verify iPhone and Watch Series 8 (remote scoring watch) are running the same build. "
            "Compares installed build number on iPhone (via devicectl) against "
            "last build artifact in /tmp/SahilStatsBuild. "
            "Watch sync is inferred from deploy log since watchOS apps cannot "
            "be enumerated via devicectl."
        ),
        "input_schema": {"type": "object", "properties": {}}
    },
    {
        "name": "ssh_run",
        "description": "Run an arbitrary command on the personal Mac.",
        "input_schema": {
            "type": "object",
            "properties": {"command": {"type": "string"}},
            "required": ["command"]
        }
    }
]

DISPATCH = {
    "read_file":            lambda i: read_file(i["path"]),
    "write_file":           lambda i: write_file(i["path"], i["content"]),
    "list_files":           lambda i: list_files(i.get("directory", "")),
    "run_local":            lambda i: run_local(i["command"]),
    "git_commit_and_push":  lambda i: git_commit_and_push(i["files"], i["message"]),
    "build":                lambda i: build(),
    "deploy_iphone":        lambda i: deploy_iphone(),
    "deploy_watch":         lambda i: deploy_watch(),
    "deploy_all":           lambda i: deploy_all(),
    "check_devices":        lambda i: check_devices(),
    "check_sync":           lambda i: check_sync(),
    "ssh_run":              lambda i: ssh_run(i["command"]),
}

# ── System prompt ──────────────────────────────────────────────────────────────

SYSTEM = """You are the autonomous lead iOS developer for SahilStatsLite.

You operate with ZERO user intervention. When given a task you:
1. Read files before editing (never assume content).
2. Make targeted, minimal code changes.
3. Commit and push with git_commit_and_push.
4. Call build to verify the changes compile.
5. If build returns errors:
   - Parse each error line for the file path and line number
   - Call read_file on each affected file
   - Fix the errors with write_file
   - Call git_commit_and_push for the fixes
   - Call build again
   - Repeat until "Build succeeded" with no errors (max 3 attempts)
6. If build is clean, call deploy_iphone then deploy_watch.
7. Report what you did concisely.

Never ask the user for confirmation. Never leave errors unfixed.
If something is genuinely ambiguous, make the most reasonable choice and proceed.

Key architecture:
- SkynetProcessor (Swift actor) owns all tracking state — no @MainActor on tracking methods
- SWIFT_STRICT_CONCURRENCY = minimal in build settings (suppresses inference warnings)
- YOLOv8n CoreML is primary person detector; fallback = VNDetectHumanRectanglesRequest
- Body pose (VNDetectHumanBodyPoseRequest) runs alongside for ankle-based court contact
- Pan-only gimbal: tall narrow ROI strip (0.25w x 0.90h) to DockKit, 2.5% X deadband
- AI frame rate: 15fps (processInterval = 0.067 in SkynetProcessor)
- Team jersey colors learned during warmup; locked in at game start (finalizeTeamColors)
- No age classifier — court bounds + body pose standing check only
- Watch sync via WCSession updateApplicationContext
- Recording: 4K H.264 at 10 Mbps, AVAssetWriter

Devices:
- iPhone: Narayan's iPhone (Series 16 Pro Max) — ios-deploy UDID 00008140-000078682693001C
- Watch:  Apple Watch Series 8 (remote scoring device) — xcrun devicectl ID 1F6B54B5-D413-548A-A90C-351867F22E2C
         (Ultra 2 is daily wear only — do not deploy to it)

No em-dashes. No placeholders. Lead with action.

Project context:
{context}
"""

# ── Agent loop ─────────────────────────────────────────────────────────────────

def run(initial: str | None = None):
    client = anthropic.Anthropic()
    context = load_context()
    system = SYSTEM.format(context=context[:10000])
    messages = []

    print("SahilStats Agent — zero-intervention mode.")
    print("Describe a task and the agent handles code, build, fix, deploy.")
    print("Type 'quit' to exit.\n")

    while True:
        if initial:
            user_input = initial
            initial = None
        else:
            try:
                user_input = input("You: ").strip()
            except (KeyboardInterrupt, EOFError):
                print("\nDone.")
                break

        if not user_input or user_input.lower() in ("quit", "q", "exit"):
            break

        messages.append({"role": "user", "content": user_input})

        while True:
            resp = client.messages.create(
                model=MODEL,
                max_tokens=8096,
                system=system,
                tools=TOOLS,
                messages=messages,
            )

            texts = [b.text for b in resp.content if hasattr(b, "text")]
            if texts:
                print(f"\nAgent: {''.join(texts)}\n")

            if resp.stop_reason != "tool_use":
                messages.append({"role": "assistant", "content": resp.content})
                break

            messages.append({"role": "assistant", "content": resp.content})
            results = []

            for block in resp.content:
                if block.type != "tool_use":
                    continue
                label = json.dumps(block.input, ensure_ascii=False)[:80]
                print(f"  [{block.name}] {label}")
                try:
                    result = DISPATCH[block.name](block.input)
                except Exception as e:
                    result = f"ERROR: {e}"
                preview = result[:400] + "…" if len(result) > 400 else result
                print(f"  → {preview}\n")
                results.append({
                    "type": "tool_result",
                    "tool_use_id": block.id,
                    "content": result,
                })

            messages.append({"role": "user", "content": results})

if __name__ == "__main__":
    run(" ".join(sys.argv[1:]) or None)
