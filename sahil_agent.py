#!/usr/bin/env python3
"""
SahilStats Agent — Full development workflow for SahilStatsLite.

Handles the complete loop autonomously:
  - Read and edit Swift files on the work Mac
  - Commit and push to GitHub
  - Pull, build, and deploy to iPhone + Apple Watch via SSH to personal Mac
  - Verify builds remotely without deploying
  - No per-command approval prompts — user launches once, agent runs freely

Usage:
  python3 sahil_agent.py
  python3 sahil_agent.py "fix the gimbal deadband"   # single-shot mode

Requirements:
  pip3 install anthropic truststore
  SSH access to narayan@Narayans-MacBook-Pro.local
  ios-deploy installed on personal Mac (/opt/homebrew/bin/ios-deploy)
"""

import os
import json
import subprocess
import sys
from pathlib import Path

import truststore
truststore.inject_into_ssl()  # Trust PAN corporate CA

import anthropic

# ── Config ────────────────────────────────────────────────────────────────────

REPO_ROOT     = Path.home() / "personal/SahilStatsLite"
PERSONAL_MAC  = "narayan@Narayans-MacBook-Pro.local"
REMOTE_REPO   = "/Users/narayan/SahilStats/SahilStatsLite/SahilStatsLite"
DEPLOY_SCRIPT = "/Users/narayan/SahilStats/deploy.sh"
MODEL         = "claude-sonnet-4-6"

# ── Load project context ───────────────────────────────────────────────────────

def load_context() -> str:
    parts = []
    for fname in ["claude.md", "HANDOFF.md"]:
        p = REPO_ROOT / fname
        if p.exists():
            parts.append(f"--- {fname} ---\n{p.read_text()}")
    return "\n\n".join(parts)

# ── Tool implementations ───────────────────────────────────────────────────────

def read_file(path: str) -> str:
    full = REPO_ROOT / path
    if not full.exists():
        return f"ERROR: {path} not found"
    return full.read_text()

def write_file(path: str, content: str) -> str:
    full = REPO_ROOT / path
    full.parent.mkdir(parents=True, exist_ok=True)
    full.write_text(content)
    return f"Written: {path}"

def list_files(directory: str = "") -> str:
    target = REPO_ROOT / directory if directory else REPO_ROOT
    if not target.exists():
        return f"ERROR: {directory} not found"
    files = sorted(
        str(f.relative_to(REPO_ROOT))
        for f in target.rglob("*")
        if f.is_file() and ".git" not in f.parts and ".DS_Store" not in str(f)
    )
    return "\n".join(files)

def run_local(command: str) -> str:
    """Run a shell command on the work Mac in the repo directory."""
    result = subprocess.run(
        command, shell=True, capture_output=True, text=True, cwd=str(REPO_ROOT)
    )
    out = result.stdout.strip()
    err = result.stderr.strip()
    return (out + ("\n" + err if err else "")).strip() or "(no output)"

def ssh_run(command: str) -> str:
    """Run an arbitrary command on the personal Mac via SSH."""
    result = subprocess.run(
        ["ssh", PERSONAL_MAC, command],
        capture_output=True, text=True, timeout=300
    )
    out = result.stdout.strip()
    err = result.stderr.strip()
    return (out + ("\n" + err if err else "")).strip() or "(no output)"

def git_commit_and_push(files: list[str], message: str) -> str:
    """Stage specific files, commit, and push to GitHub."""
    output = []

    # Stage files
    for f in files:
        r = subprocess.run(["git", "add", f], capture_output=True, text=True, cwd=str(REPO_ROOT))
        if r.returncode != 0:
            return f"git add failed for {f}: {r.stderr}"
        output.append(f"Staged: {f}")

    # Commit
    full_message = f"{message}\n\nCo-Authored-By: Claude Sonnet 4.6 (1M context) <noreply@anthropic.com>"
    r = subprocess.run(
        ["git", "commit", "-m", full_message],
        capture_output=True, text=True, cwd=str(REPO_ROOT)
    )
    if r.returncode != 0:
        return f"git commit failed: {r.stderr}"
    output.append(f"Committed: {message[:60]}")

    # Push
    r = subprocess.run(
        ["git", "push", "origin", "main"],
        capture_output=True, text=True, cwd=str(REPO_ROOT), timeout=30
    )
    if r.returncode != 0:
        return f"git push failed: {r.stderr}"
    output.append("Pushed to GitHub.")
    return "\n".join(output)

def build_only() -> str:
    """Pull latest on personal Mac and build (no deploy). Returns build result."""
    cmd = f"""
set -e
cd {REMOTE_REPO}
git pull origin main 2>&1 | tail -3
echo '==> Building...'
xcodebuild \\
  -scheme SahilStatsLite \\
  -configuration Debug \\
  -destination 'generic/platform=iOS' \\
  -derivedDataPath /tmp/SahilStatsBuild \\
  -allowProvisioningUpdates \\
  DEVELOPMENT_TEAM=TTV9QQRD5H \\
  CODE_SIGN_STYLE=Automatic \\
  2>&1 | grep -E '^.*error:|Build succeeded|Build FAILED' | head -30
"""
    result = subprocess.run(
        ["ssh", PERSONAL_MAC, "bash", "-s"],
        input=cmd, capture_output=True, text=True, timeout=300
    )
    out = result.stdout.strip()
    err = result.stderr.strip()
    return (out + ("\n" + err if err else "")).strip()

def deploy() -> str:
    """Pull, build, and deploy to iPhone (Watch deploys automatically as companion)."""
    result = subprocess.run(
        ["ssh", PERSONAL_MAC, f"bash {DEPLOY_SCRIPT}"],
        capture_output=True, text=True, timeout=600
    )
    out = result.stdout.strip()
    err = result.stderr.strip()
    combined = (out + ("\n" + err if err else "")).strip()
    if "Done!" in combined:
        return combined
    return f"Deploy output:\n{combined}"

def check_device() -> str:
    """Check if iPhone is reachable (USB or WiFi)."""
    result = subprocess.run(
        ["ssh", PERSONAL_MAC, "/opt/homebrew/bin/ios-deploy --detect --timeout 5"],
        capture_output=True, text=True, timeout=15
    )
    out = (result.stdout + result.stderr).strip()
    if "Narayan's iPhone" in out:
        lines = [l for l in out.splitlines() if "Narayan" in l or "Found" in l]
        return "Device found:\n" + "\n".join(lines)
    return "Device not found. Connect iPhone via USB or ensure WiFi sync is enabled in Xcode."

# ── Tool definitions for Claude ────────────────────────────────────────────────

TOOLS = [
    {
        "name": "read_file",
        "description": "Read a Swift file from the local SahilStatsLite repo. Path relative to repo root.",
        "input_schema": {
            "type": "object",
            "properties": {"path": {"type": "string", "description": "Relative path, e.g. SahilStatsLite/Services/AutoZoomManager.swift"}},
            "required": ["path"]
        }
    },
    {
        "name": "write_file",
        "description": "Write or overwrite a file in the repo. Always read the file first before writing.",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string"},
                "content": {"type": "string", "description": "Full file content"}
            },
            "required": ["path", "content"]
        }
    },
    {
        "name": "list_files",
        "description": "List all files in the repo or a subdirectory.",
        "input_schema": {
            "type": "object",
            "properties": {"directory": {"type": "string", "description": "Subdirectory to list (optional)"}}
        }
    },
    {
        "name": "run_local",
        "description": "Run a shell command on the work Mac in the repo directory. Use for git status, diff, log.",
        "input_schema": {
            "type": "object",
            "properties": {"command": {"type": "string"}},
            "required": ["command"]
        }
    },
    {
        "name": "ssh_run",
        "description": "Run an arbitrary command on the personal Mac via SSH. Use for checking git log, device state, etc.",
        "input_schema": {
            "type": "object",
            "properties": {"command": {"type": "string"}},
            "required": ["command"]
        }
    },
    {
        "name": "git_commit_and_push",
        "description": "Stage specific files, commit with a message, and push to GitHub. Call after making code changes.",
        "input_schema": {
            "type": "object",
            "properties": {
                "files": {"type": "array", "items": {"type": "string"}, "description": "Relative file paths to stage"},
                "message": {"type": "string", "description": "Commit message"}
            },
            "required": ["files", "message"]
        }
    },
    {
        "name": "build_only",
        "description": "Pull latest on personal Mac and run xcodebuild. Returns build success or error output. Use to verify changes compile before deploying.",
        "input_schema": {"type": "object", "properties": {}}
    },
    {
        "name": "deploy",
        "description": "Pull latest, build, and deploy to Narayan's iPhone via ios-deploy. Watch app deploys automatically as a companion. Phone must be on USB or same WiFi with network sync enabled.",
        "input_schema": {"type": "object", "properties": {}}
    },
    {
        "name": "check_device",
        "description": "Check if Narayan's iPhone is reachable via USB or WiFi. Call before deploy if unsure.",
        "input_schema": {"type": "object", "properties": {}}
    }
]

# ── Tool dispatcher ────────────────────────────────────────────────────────────

def dispatch(name: str, inp: dict) -> str:
    match name:
        case "read_file":          return read_file(inp["path"])
        case "write_file":         return write_file(inp["path"], inp["content"])
        case "list_files":         return list_files(inp.get("directory", ""))
        case "run_local":          return run_local(inp["command"])
        case "ssh_run":            return ssh_run(inp["command"])
        case "git_commit_and_push": return git_commit_and_push(inp["files"], inp["message"])
        case "build_only":         return build_only()
        case "deploy":             return deploy()
        case "check_device":       return check_device()
        case _:                    return f"Unknown tool: {name}"

# ── Agent loop ─────────────────────────────────────────────────────────────────

SYSTEM = """You are the lead iOS developer for SahilStatsLite — a SwiftUI app that records
Narayan's son Sahil's AAU basketball games with AI tracking (Skynet), score overlay,
and Apple Watch companion. You have complete autonomy to read, edit, build, and deploy.

Your workflow:
1. Read files before editing them. Never assume file content.
2. After code changes: commit and push with git_commit_and_push.
3. Use build_only to verify before deploying. Fix any build errors first.
4. Use deploy to push to iPhone (Watch app deploys automatically).
5. Be concise. Lead with action. No em-dashes. No placeholders.

Key architecture facts:
- Vision/Kalman runs on SkynetProcessor (Swift actor), off main thread.
- YOLO v8n CoreML is the primary person detector (falls back to VNDetectHumanRectanglesRequest).
- Gimbal is pan-only (tall narrow ROI strip to DockKit). 2.5% X deadband.
- AI frame rate: 15fps (processInterval = 0.067 in SkynetProcessor).
- Recording: 4K H.264 at 10 Mbps via AVAssetWriter.
- Watch app syncs via WCSession updateApplicationContext.

Project context:
{context}
"""

def run_agent(initial_message: str | None = None):
    client = anthropic.Anthropic()
    context = load_context()
    system = SYSTEM.format(context=context[:8000])  # Trim if huge

    messages = []
    print("SahilStats Agent ready. Commands: 'deploy', 'build', 'check device', or describe any task.")
    print("Type 'quit' or Ctrl+C to exit.\n")

    while True:
        # Get input
        if initial_message:
            user_input = initial_message
            initial_message = None
        else:
            try:
                user_input = input("You: ").strip()
            except (KeyboardInterrupt, EOFError):
                print("\nExiting.")
                break

        if not user_input:
            continue
        if user_input.lower() in ("quit", "exit", "q"):
            break

        messages.append({"role": "user", "content": user_input})

        # Agentic loop
        while True:
            response = client.messages.create(
                model=MODEL,
                max_tokens=8096,
                system=system,
                tools=TOOLS,
                messages=messages
            )

            # Print text output
            text_parts = [b.text for b in response.content if hasattr(b, "text")]
            if text_parts:
                print(f"\nAgent: {''.join(text_parts)}\n")

            if response.stop_reason != "tool_use":
                messages.append({"role": "assistant", "content": response.content})
                break

            messages.append({"role": "assistant", "content": response.content})
            tool_results = []

            for block in response.content:
                if block.type != "tool_use":
                    continue
                print(f"  [{block.name}] {json.dumps(block.input, ensure_ascii=False)[:100]}")
                result = dispatch(block.name, block.input)
                preview = result[:300] + "..." if len(result) > 300 else result
                print(f"  -> {preview}\n")
                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": block.id,
                    "content": result
                })

            messages.append({"role": "user", "content": tool_results})

if __name__ == "__main__":
    # Optional: pass a task as a command-line argument for single-shot mode
    initial = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else None
    run_agent(initial)
