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

FILE_RE = re.compile(
    r"###\s*FILE:\s*[`']?([^\s`']+)[`']?\s*\n```(?:[\w.+-]*)\n(.*?)```",
    re.S,
)
FILE_RE_ALT = re.compile(
    r"###\s*FILE:\s*[`']?([^\s`']+)[`']?\s*\n(.*?)(?=\n###\s*(?:FILE:|END FILE)|\Z)",
    re.S,
)

SCRIPT_DIR = Path(__file__).resolve().parent
PRD_PATH = SCRIPT_DIR / "prd.json"
PROGRESS_PATH = SCRIPT_DIR / "progress.txt"
LAST_VERIFY = SCRIPT_DIR / "LAST_VERIFY.txt"
QWEN_MD = SCRIPT_DIR / "QWEN.md"
BRIEF_PATH = SCRIPT_DIR / "BRIEF.md"

QWEN_SSH = os.environ.get("QWEN_SSH", "studio")
QWEN_API = os.environ.get("QWEN_API", "http://127.0.0.1:1234/v1/chat/completions")
QWEN_MODEL = os.environ.get("QWEN_MODEL", "mlx-community/Qwen3.8-27B-8bit")

SKIP_DIR_NAMES = {
    ".git",
    "node_modules",
    ".next",
    "dist",
    "build",
    "DerivedData",
    "archive",
    ".turbo",
    "coverage",
}
SKIP_COMMIT_PATHS = [
    "node_modules",
    ".next",
    "DerivedData",
    "dist",
    "build",
    "coverage",
    "scripts/ralph/LAST_REPLY.md",
    "scripts/ralph/LAST_THINKING.md",
    "scripts/ralph/LAST_VERIFY.txt",
]
SOURCE_SUFFIXES = {
    ".ts",
    ".tsx",
    ".js",
    ".jsx",
    ".mjs",
    ".cjs",
    ".css",
    ".scss",
    ".html",
    ".json",
    ".md",
    ".swift",
    ".plist",
    ".pbxproj",
}


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
        "temperature": 0.8,
        "top_p": 0.95,
        "top_k": 20,
        "max_tokens": 65536,
        "stream": False,
        "reasoning_effort": "high",
        "chat_template_kwargs": {
            "enable_thinking": True,
            "preserve_thinking": True,
        },
    }
    body = json.dumps(payload)
    if QWEN_SSH:
        remote = (
            f"curl -sS -m 3600 {QWEN_API} "
            f"-H 'Content-Type: application/json' -d @-"
        )
        raw = subprocess.check_output(
            ["ssh", QWEN_SSH, remote], input=body.encode(), timeout=3700
        )
    else:
        import urllib.request

        req = urllib.request.Request(
            QWEN_API,
            data=body.encode(),
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
    if not content and think:
        # Some templates dump the files into reasoning. Still try to extract.
        content = think
    return content


def safe_rel(path: str) -> str | None:
    rel = path.strip().strip("`").strip("'").strip('"')
    if rel.startswith("./"):
        rel = rel[2:]
    rel = rel.lstrip("/")
    if not rel or rel in {"path", "relative/path", "relative/path.ext", "relative/path.tsx"}:
        return None
    parts = Path(rel).parts
    if ".." in parts:
        return None
    if parts[0] in SKIP_DIR_NAMES:
        return None
    return rel


def write_files(text: str, dest: Path) -> list[str]:
    written: list[str] = []
    pairs = FILE_RE.findall(text)
    if not pairs:
        pairs = FILE_RE_ALT.findall(text)
    for path, content in pairs:
        rel = safe_rel(path)
        if not rel:
            continue
        body = content
        if body.startswith("```"):
            body = re.sub(r"^```[\w.+-]*\n", "", body, count=1)
        body = re.sub(r"\n```\s*$", "\n", body)
        body = re.sub(r"\n###\s*END FILE\s*$", "\n", body)
        fp = dest / rel
        fp.parent.mkdir(parents=True, exist_ok=True)
        fp.write_text(body if body.endswith("\n") else body + "\n")
        written.append(rel)
        print(f"  wrote {rel} ({len(body)} bytes)", flush=True)
    return written


def run_verify(cmd: str, cwd: Path) -> tuple[bool, str]:
    print(f"  VERIFY: {cmd}", flush=True)
    env = os.environ.copy()
    env.setdefault("CI", "true")
    try:
        p = subprocess.run(
            cmd,
            shell=True,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=900,
            env=env,
        )
        out = (p.stdout or "") + (p.stderr or "")
        ok = p.returncode == 0
    except subprocess.TimeoutExpired as exc:
        out = (exc.stdout or "") + (exc.stderr or "") + "\nVERIFY timed out after 900s"
        ok = False
    print(out[-4000:] if len(out) > 4000 else out)
    return ok, out


def extract_verify_cmd(story: dict) -> str:
    if story.get("verify"):
        return str(story["verify"])
    return "true"


def ensure_gitignore(root: Path) -> None:
    gi = root / ".gitignore"
    needed = [
        "node_modules/",
        ".next/",
        "dist/",
        "build/",
        "DerivedData/",
        ".DS_Store",
        "coverage/",
        "*.tsbuildinfo",
        "scripts/ralph/LAST_REPLY.md",
        "scripts/ralph/LAST_THINKING.md",
        "scripts/ralph/LAST_VERIFY.txt",
    ]
    existing = gi.read_text() if gi.exists() else ""
    missing = [line for line in needed if line not in existing]
    if missing:
        extra = ("\n" if existing and not existing.endswith("\n") else "") + "\n".join(missing) + "\n"
        gi.write_text(existing + extra)


def commit(root: Path, story: dict) -> None:
    ensure_gitignore(root)
    subprocess.run(
        ["git", "rm", "-r", "--cached", "--ignore-unmatch", *SKIP_COMMIT_PATHS],
        cwd=root,
        check=False,
        capture_output=True,
        text=True,
    )
    subprocess.run(["git", "add", "-A"], cwd=root, check=False)
    subprocess.run(
        ["git", "reset", "-q", "--", *SKIP_COMMIT_PATHS],
        cwd=root,
        check=False,
    )
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


def tree_snapshot(root: Path) -> str:
    lines: list[str] = []
    for p in sorted(root.rglob("*")):
        if any(part in SKIP_DIR_NAMES or part == "scripts" for part in p.relative_to(root).parts):
            continue
        if p.is_file():
            rel = p.relative_to(root).as_posix()
            lines.append(f"{rel} ({p.stat().st_size} bytes)")
    return "\n".join(lines[:200]) or "(empty project)"


def file_snapshot(root: Path) -> str:
    chunks: list[str] = []
    total = 0
    for p in sorted(root.rglob("*")):
        rel_parts = p.relative_to(root).parts
        if any(part in SKIP_DIR_NAMES or part == "scripts" for part in rel_parts):
            continue
        if not p.is_file() or p.suffix.lower() not in SOURCE_SUFFIXES:
            continue
        if p.name in {"package-lock.json", "pnpm-lock.yaml"}:
            continue
        if p.stat().st_size > 80_000:
            chunks.append(f"===== {p.relative_to(root)} =====\n[skipped, {p.stat().st_size} bytes]\n")
            continue
        text = p.read_text(errors="replace")
        if total + len(text) > 55_000:
            chunks.append(f"===== {p.relative_to(root)} =====\n[truncated for context]\n")
            break
        chunks.append(f"===== {p.relative_to(root)} =====\n{text}")
        total += len(text)
    return "\n\n".join(chunks) or "(no source files yet)"


def build_user_prompt(root: Path, story: dict, prd: dict) -> str:
    progress = PROGRESS_PATH.read_text() if PROGRESS_PATH.exists() else ""
    last = LAST_VERIFY.read_text() if LAST_VERIFY.exists() else "(none)"
    brief = BRIEF_PATH.read_text() if BRIEF_PATH.exists() else "(none)"
    verify = extract_verify_cmd(story)
    return (
        "You are implementing ONE Ralph story. Emit complete ### FILE blocks.\n"
        "If you do not emit ### FILE blocks the iteration is a hard fail.\n\n"
        f"PROJECT ROOT: {root}\n\n"
        f"CURRENT STORY:\n{json.dumps(story, indent=2)}\n\n"
        f"AUTHORITATIVE VERIFY (copy this exact line at the end):\nVERIFY: {verify}\n\n"
        f"YOUTUBE BRIEF:\n{brief}\n\n"
        f"FULL PRD:\n{json.dumps(prd, indent=2)}\n\n"
        f"PROJECT TREE:\n{tree_snapshot(root)}\n\n"
        f"EXISTING SOURCE (edit these; do not start over):\n{file_snapshot(root)}\n\n"
        f"PROGRESS.TXT (tail):\n{progress[-6000:]}\n\n"
        f"LAST_VERIFY.TXT:\n{last[-5000:]}\n\n"
        "Start your reply with ### FILE: and output every file this story needs.\n"
    )


def main() -> int:
    root = repo_root()
    ensure_gitignore(root)
    prd = load_prd()
    if all_passed(prd):
        print("<promise>COMPLETE</promise>")
        return 0
    story = next_story(prd)
    if story is None:
        print("<promise>COMPLETE</promise>")
        return 0

    user = build_user_prompt(root, story, prd)
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
        print("  no FILE blocks — retrying once with a stricter prompt", flush=True)
        try:
            retry = chat(
                user
                + "\n\nCRITICAL: your previous reply had ZERO ### FILE blocks. "
                "Reply with ONLY file blocks. First characters must be: ### FILE:\n"
            )
            (SCRIPT_DIR / "LAST_REPLY.md").write_text(retry)
            written = write_files(retry, root)
            reply = retry
        except Exception as exc:
            print(f"Qwen retry failed: {exc}", flush=True)

    if not written:
        LAST_VERIFY.write_text("no ### FILE blocks in model output\n" + reply[-2000:])
        append_progress(story, [], False, "no files emitted")
        return 0

    cmd = extract_verify_cmd(story)
    ok, out = run_verify(cmd, root)
    LAST_VERIFY.write_text(out[-12000:])
    if ok:
        fresh = load_prd()
        for s in fresh["userStories"]:
            if s["id"] == story["id"]:
                s["passes"] = True
        PRD_PATH.write_text(json.dumps(fresh, indent=2) + "\n")
        commit(root, story)
        append_progress(story, written, True, "checks passed")
        if all_passed(fresh):
            print("<promise>COMPLETE</promise>")
    else:
        append_progress(
            story,
            written,
            False,
            "checks FAILED — next iteration must fix LAST_VERIFY.txt",
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
