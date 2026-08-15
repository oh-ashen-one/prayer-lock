#!/usr/bin/env python3
"""One Ralph iteration against Studio Qwen. Fresh context. Memory via prd/progress/git."""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

FILE_RE = re.compile(r"### FILE:\s*(\S+)\s*\n```(?:[\w.+-]+)?\n(.*?)```", re.S)

SCRIPT_DIR = Path(__file__).resolve().parent
PRD_PATH = SCRIPT_DIR / "prd.json"
PROGRESS_PATH = SCRIPT_DIR / "progress.txt"
LAST_VERIFY = SCRIPT_DIR / "LAST_VERIFY.txt"
QWEN_MD = SCRIPT_DIR / "QWEN.md"

# Laptop -> Studio API. On the Studio, leave QWEN_SSH empty.
QWEN_SSH = os.environ.get("QWEN_SSH", "studio")
QWEN_API = os.environ.get("QWEN_API", "http://127.0.0.1:1234/v1/chat/completions")
QWEN_MODEL = os.environ.get("QWEN_MODEL", "mlx-community/Qwen3.8-27B-8bit")


def repo_root() -> Path:
    out = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True)
    return Path(out.strip())


def load_prd() -> dict:
    return json.loads(PRD_PATH.read_text())


def next_story(prd: dict) -> dict | None:
    stories = [s for s in prd.get("userStories", []) if not s.get("passes")]
    if not stories:
        return None
    return sorted(stories, key=lambda s: s.get("priority", 999))[0]


def all_passed(prd: dict) -> bool:
    stories = prd.get("userStories") or []
    return bool(stories) and all(s.get("passes") for s in stories)


def chat(user: str) -> str:
    payload = {
        "model": QWEN_MODEL,
        "messages": [
            {"role": "system", "content": QWEN_MD.read_text()},
            {"role": "user", "content": user},
        ],
        "temperature": 1.0,
        "top_p": 0.95,
        "top_k": 20,
        "max_tokens": 65536,
        "stream": False,
        "reasoning_effort": "xhigh",
        "chat_template_kwargs": {
            "enable_thinking": True,
            "preserve_thinking": True,
        },
    }
    body = json.dumps(payload)
    if QWEN_SSH:
        cmd = [
            "ssh", QWEN_SSH,
            "curl", "-sS", "-m", "3600", QWEN_API,
            "-H", "Content-Type: application/json",
            "-d", "@-",
        ]
        raw = subprocess.check_output(cmd, input=body.encode(), timeout=3700)
    else:
        import urllib.request
        req = urllib.request.Request(
            QWEN_API, data=body.encode(),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=3600) as resp:
            raw = resp.read()
    data = json.loads(raw)
    msg = data["choices"][0]["message"]
    content = msg.get("content") or ""
    think = msg.get("reasoning_content") or ""
    if think:
        (SCRIPT_DIR / "LAST_THINKING.md").write_text(think)
    return content


def write_files(text: str, dest: Path) -> list[str]:
    written = []
    for path, content in FILE_RE.findall(text):
        rel = path.strip().lstrip("./")
        if rel.startswith("/") or ".." in Path(rel).parts:
            continue
        if rel in {"path", "relative/path.ext"}:
            continue
        fp = dest / rel
        fp.parent.mkdir(parents=True, exist_ok=True)
        fp.write_text(content if content.endswith("\n") else content + "\n")
        written.append(rel)
        print(f"  wrote {rel} ({len(content)} bytes)", flush=True)
    return written


def run_verify(cmd: str, cwd: Path) -> tuple[bool, str]:
    print(f"  VERIFY: {cmd}", flush=True)
    p = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True)
    out = (p.stdout or "") + (p.stderr or "")
    ok = p.returncode == 0
    print(out[-4000:] if len(out) > 4000 else out)
    return ok, out


def extract_verify_cmd(text: str, story: dict) -> str:
    m = re.search(r"^VERIFY:\s*(.+)$", text, re.M)
    if m:
        return m.group(1).strip()
    if story.get("verify"):
        return str(story["verify"])
    return "true"


def commit(root: Path, story: dict) -> None:
    subprocess.run(["git", "add", "-A"], cwd=root, check=False)
    msg = f"feat: [{story['id']}] {story['title']}"
    subprocess.run(["git", "commit", "-m", msg], cwd=root, check=False)


def append_progress(story: dict, written: list[str], verify_ok: bool, note: str) -> None:
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    block = (
        f"\n## {ts} - {story['id']}\n"
        f"- verify_ok: {verify_ok}\n"
        f"- files: {', '.join(written) or '(none)'}\n"
        f"- {note}\n---\n"
    )
    with PROGRESS_PATH.open("a") as f:
        f.write(block)


def main() -> int:
    root = repo_root()
    prd = load_prd()
    if all_passed(prd):
        print("<promise>COMPLETE</promise>")
        return 0
    story = next_story(prd)
    if story is None:
        print("<promise>COMPLETE</promise>")
        return 0

    progress = PROGRESS_PATH.read_text() if PROGRESS_PATH.exists() else ""
    last = LAST_VERIFY.read_text() if LAST_VERIFY.exists() else "(none)"
    user = (
        f"PROJECT ROOT: {root}\n"
        f"CURRENT STORY:\n{json.dumps(story, indent=2)}\n\n"
        f"FULL PRD:\n{json.dumps(prd, indent=2)}\n\n"
        f"PROGRESS.TXT:\n{progress[-8000:]}\n\n"
        f"LAST_VERIFY.TXT:\n{last[-6000:]}\n"
    )
    print(f"Story {story['id']}: {story['title']}", flush=True)
    try:
        reply = chat(user)
    except Exception as exc:
        print(f"Qwen API failed: {exc}", flush=True)
        LAST_VERIFY.write_text(str(exc))
        return 1

    (SCRIPT_DIR / "LAST_REPLY.md").write_text(reply)
    written = write_files(reply, root)
    if not written:
        LAST_VERIFY.write_text("no ### FILE blocks in model output\n" + reply[-2000:])
        append_progress(story, [], False, "no files emitted")
        return 0

    cmd = extract_verify_cmd(reply, story)
    ok, out = run_verify(cmd, root)
    LAST_VERIFY.write_text(out[-12000:])
    if ok:
        for s in prd["userStories"]:
            if s["id"] == story["id"]:
                s["passes"] = True
        PRD_PATH.write_text(json.dumps(prd, indent=2) + "\n")
        commit(root, story)
        append_progress(story, written, True, "checks passed")
        if all_passed(prd):
            print("<promise>COMPLETE</promise>")
    else:
        append_progress(story, written, False, "checks FAILED — next iteration must fix LAST_VERIFY.txt")
    return 0


if __name__ == "__main__":
    sys.exit(main())
