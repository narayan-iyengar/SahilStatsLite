#!/usr/bin/env python3
"""
SahilStatsLite Gemini Dev Agent
Runs on personal Mac. Edits the local repo and pushes to GitHub directly.

Setup:
  python3 -m venv ~/sahil-agent-env
  source ~/sahil-agent-env/bin/activate
  pip install google-genai
  export GEMINI_API_KEY=your_key_from_aistudio.google.com
  python3 gemini_agent.py
"""

import os
import subprocess
import json
from pathlib import Path
from google import genai
from google.genai import types

# ── Config ────────────────────────────────────────────────────────────────────

REPO_ROOT = Path("/Users/narayan/SahilStats/SahilStatsLite/SahilStatsLite")
MODEL = "gemini-2.0-flash"

# ── Load project context ───────────────────────────────────────────────────────

def load_project_context() -> str:
    context = ""
    for fname in ["claude.md", "Gemini.md", "HANDOFF.md"]:
        p = REPO_ROOT / fname
        if p.exists():
            context += f"\n\n--- {fname} ---\n{p.read_text()}"
    return context.strip()

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
    files = []
    for f in sorted(target.rglob("*")):
        if f.is_file() and ".git" not in f.parts and ".DS_Store" not in str(f):
            files.append(str(f.relative_to(REPO_ROOT)))
    return "\n".join(files)

def run_command(command: str) -> str:
    result = subprocess.run(
        command, shell=True, capture_output=True, text=True,
        cwd=str(REPO_ROOT)
    )
    out = result.stdout.strip()
    err = result.stderr.strip()
    return (out + ("\n" + err if err else "")).strip() or "(no output)"

def git_commit_and_push(files: list, commit_message: str) -> str:
    add_args = " ".join(f'"{f}"' for f in files)
    script = f"""
set -e
cd {REPO_ROOT}
git add {add_args}
git commit -m "{commit_message}

Co-Authored-By: Gemini 2.0 Flash <noreply@google.com>"
git push origin main
echo "PUSHED OK"
"""
    result = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
    out = result.stdout.strip()
    err = result.stderr.strip()
    if "PUSHED OK" in out:
        return "Committed and pushed to GitHub successfully."
    return f"Output:\n{out}\n{err}"

# ── Tool dispatcher ────────────────────────────────────────────────────────────

def dispatch(name: str, args: dict) -> str:
    if name == "read_file":
        return read_file(args["path"])
    elif name == "write_file":
        return write_file(args["path"], args["content"])
    elif name == "list_files":
        return list_files(args.get("directory", ""))
    elif name == "run_command":
        return run_command(args["command"])
    elif name == "git_commit_and_push":
        return git_commit_and_push(args["files"], args["commit_message"])
    return f"Unknown tool: {name}"

# ── Tool schema (new google-genai format) ─────────────────────────────────────

TOOL_DECLARATIONS = [
    {
        "name": "read_file",
        "description": "Read a file from the SahilStatsLite repo. Path is relative to repo root.",
        "parameters": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "e.g. SahilStatsLite/Services/AutoZoomManager.swift"}
            },
            "required": ["path"]
        }
    },
    {
        "name": "write_file",
        "description": "Write or overwrite a file in the repo.",
        "parameters": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Relative path from repo root"},
                "content": {"type": "string", "description": "Full file content to write"}
            },
            "required": ["path", "content"]
        }
    },
    {
        "name": "list_files",
        "description": "List files in the repo or a subdirectory.",
        "parameters": {
            "type": "object",
            "properties": {
                "directory": {"type": "string", "description": "Subdirectory to list (optional)"}
            }
        }
    },
    {
        "name": "run_command",
        "description": "Run a shell command in the repo directory.",
        "parameters": {
            "type": "object",
            "properties": {
                "command": {"type": "string", "description": "Shell command to run"}
            },
            "required": ["command"]
        }
    },
    {
        "name": "git_commit_and_push",
        "description": "Commit specified files and push to GitHub.",
        "parameters": {
            "type": "object",
            "properties": {
                "files": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Relative file paths to commit"
                },
                "commit_message": {"type": "string", "description": "Git commit message"}
            },
            "required": ["files", "commit_message"]
        }
    }
]

# ── Agent loop ─────────────────────────────────────────────────────────────────

def main():
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        print("ERROR: GEMINI_API_KEY not set. Get one free at aistudio.google.com")
        return

    client = genai.Client(api_key=api_key)
    project_context = load_project_context()

    system = f"""You are the lead iOS developer for SahilStatsLite, a SwiftUI app that records
Narayan's son Sahil's AAU basketball games with AI tracking, score overlay, and Watch companion.

Your job:
- Read and modify Swift files in the repo
- Make requested code changes -- always read a file before editing it
- After changes, use git_commit_and_push to deploy to GitHub
- Be concise and direct. Lead with action.
- Never use em-dashes. Write complete working code. No placeholders.

IMPORTANT architectural rules -- do not violate:
- DockKit system tracking must stay DISABLED (setSystemTrackingEnabled false).
  Skynet (AutoZoomManager) is the sole tracking brain.
- AI frame rate is 15fps (aiFrameInterval: 0.067). Do not lower it.
- GimbalTrackingManager.updateTrackingROI(center:) steers the physical gimbal.
  Do not remove this.

Project context:
{project_context}
"""

    config = types.GenerateContentConfig(
        system_instruction=system,
        tools=[types.Tool(function_declarations=TOOL_DECLARATIONS)]
    )

    chat = client.chats.create(model=MODEL, config=config)
    print(f"SahilStatsLite Gemini Agent ready ({MODEL}). Type your request. Ctrl+C to exit.\n")

    while True:
        try:
            user_input = input("You: ").strip()
        except (KeyboardInterrupt, EOFError):
            print("\nExiting.")
            break

        if not user_input:
            continue

        message = user_input

        # Agentic loop -- keep going until Gemini stops calling tools
        while True:
            response = chat.send_message(message)
            candidate = response.candidates[0]
            parts = candidate.content.parts

            # Collect any text
            text_parts = [p.text for p in parts if hasattr(p, "text") and p.text]
            if text_parts:
                print(f"\nAgent: {''.join(text_parts)}\n")

            # Find function calls
            fn_calls = [p for p in parts if hasattr(p, "function_call") and p.function_call]

            if not fn_calls:
                break  # No more tool calls, done

            # Execute all tool calls and collect results
            tool_results = []
            for part in fn_calls:
                fc = part.function_call
                args = {k: v for k, v in fc.args.items()}
                print(f"  [{fc.name}] {json.dumps(args, ensure_ascii=False)[:120]}")
                result = dispatch(fc.name, args)
                preview = result[:200] + "..." if len(result) > 200 else result
                print(f"  -> {preview}\n")
                tool_results.append(
                    types.Part(
                        function_response=types.FunctionResponse(
                            name=fc.name,
                            response={"result": result}
                        )
                    )
                )

            message = tool_results

if __name__ == "__main__":
    main()
