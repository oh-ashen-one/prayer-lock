#!/usr/bin/env python3
"""One Ralph iteration against Studio Qwen. Fresh context. Memory via prd/progress/git."""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import threading
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
ALLOWED_FILES: set = set()

QWEN_SSH = os.environ.get("QWEN_SSH", "studio")
QWEN_API = os.environ.get("QWEN_API", "http://127.0.0.1:1234/v1/chat/completions")
QWEN_MODEL = os.environ.get("QWEN_MODEL", "ralph-showcase")

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
    "__pycache__",
}
SKIP_COMMIT_PATHS = [
    "node_modules",
    ".next",
    "DerivedData",
    "dist",
    "build",
    "coverage",
    "__pycache__",
    "scripts/ralph/__pycache__",
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


def _consume_sse(stream, content_parts: list[str], think_parts: list[str]) -> None:
    n = 0
    for raw_line in stream:
        line = raw_line.decode("utf-8", errors="replace").strip()
        if not line.startswith("data:"):
            continue
        data = line[5:].strip()
        if data == "[DONE]":
            break
        try:
            chunk = json.loads(data)
        except json.JSONDecodeError:
            continue
        choices = chunk.get("choices") or [{}]
        delta = (choices[0] or {}).get("delta") or {}
        if delta.get("content"):
            content_parts.append(delta["content"])
        if delta.get("reasoning_content"):
            think_parts.append(delta["reasoning_content"])
        n += 1
        if n % 25 == 0:
            reply = "".join(content_parts)
            think_so_far = "".join(think_parts)
            (SCRIPT_DIR / "LAST_REPLY.md").write_text(reply)
            (SCRIPT_DIR / "LAST_THINKING.md").write_text(think_so_far)
            blob = reply if has_file_blocks(reply) else think_so_far
            try:
                write_files(blob, repo_root())
            except Exception as exc:
                print(f"  mid-stream write skipped: {exc}", flush=True)


def chat(user: str) -> str:
    # LMS Qwen3.8 ignores enable_thinking=false and dumps every token into
    # reasoning_content. Prefilling </think> makes content come back as text.
    payload = {
        "model": QWEN_MODEL,
        "messages": [
            {"role": "system", "content": QWEN_MD.read_text()},
            {"role": "user", "content": user},
            {"role": "assistant", "content": "</think>\n"},
        ],
        "temperature": 0.7,
        "top_p": 0.9,
        "top_k": 20,
        "max_tokens": 16384,
        "stream": True,
        "enable_thinking": False,
        "reasoning_effort": "low",
        "chat_template_kwargs": {
            "enable_thinking": False,
            "preserve_thinking": False,
        },
    }
    body = json.dumps(payload)
    content_parts: list[str] = []
    think_parts: list[str] = []
    if QWEN_SSH:
        remote = (
            f"curl -sS -N -m 1800 {QWEN_API} "
            f"-H 'Content-Type: application/json' -d @-"
        )
        proc = subprocess.Popen(
            ["ssh", QWEN_SSH, remote],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )
        assert proc.stdin and proc.stdout

        def _kill() -> None:
            try:
                os.killpg(proc.pid, 9)
            except OSError:
                proc.kill()

        timer = threading.Timer(1810, _kill)
        timer.daemon = True
        timer.start()
        try:
            proc.stdin.write(body.encode())
            proc.stdin.close()
            _consume_sse(proc.stdout, content_parts, think_parts)
            proc.wait(timeout=20)
        except Exception:
            _kill()
            raise
        finally:
            timer.cancel()
            if proc.poll() is None:
                _kill()
    else:
        import urllib.request

        req = urllib.request.Request(
            QWEN_API,
            data=body.encode(),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=1800) as resp:
            _consume_sse(resp, content_parts, think_parts)
    content = "".join(content_parts)
    think = "".join(think_parts)
    (SCRIPT_DIR / "LAST_REPLY.md").write_text(content)
    if think:
        (SCRIPT_DIR / "LAST_THINKING.md").write_text(think)
    # If LMS still hid the files in reasoning, take them from there.
    if not has_file_blocks(content) and think and has_file_blocks(think):
        content = think
    return content


def has_file_blocks(text: str) -> bool:
    return bool(text and re.search(r"###\s*FILE:\s*\S+", text))


def safe_rel(path: str) -> str | None:
    rel = path.strip().strip("`").strip("'").strip('"')
    if rel.startswith("./"):
        rel = rel[2:]
    # Only slashes — never lstrip(".") or the set "./" (that turns .gitignore into gitignore).
    rel = rel.lstrip("/")
    if rel == "gitignore":
        rel = ".gitignore"
    if not rel or rel in {"path", "relative/path", "relative/path.ext", "relative/path.tsx"}:
        return None
    parts = Path(rel).parts
    if ".." in parts:
        return None
    if parts[0] in SKIP_DIR_NAMES:
        return None
    return rel


HEADER_RE = re.compile(r"###\s*FILE:\s*[`']?([^\s`']+)[`']?[^\n]*\n")
MARKER_LINE_RE = re.compile(r"(?m)^###\s*(?:END FILE|FILE:)\b")
PLANNING_HEAD = re.compile(
    r"^(Complete file\.?|Copy existing|Full rewrite|Let me |I'll |I will |Now let |Wait[, ]|Hmm[, ])",
    re.I,
)


def _looks_like_planning(body: str) -> bool:
    head = body.lstrip()
    if PLANNING_HEAD.match(head) or head.startswith("### "):
        return True
    return False


def _clean_file_body(body: str) -> str:
    body = body.replace("\r\n", "\n")
    body = re.sub(r"^```[\w.+-]*\n", "", body)
    # Headers win: never let a missing closer swallow the next file.
    body = re.split(r"\n###\s*(?:END FILE|FILE:)\b", body, maxsplit=1)[0]
    body = re.sub(r"(?m)^###\s*(?:END FILE|FILE:).*\n?", "", body)
    body = re.sub(r"\n```[ \t]*\Z", "\n", body)
    return body if body.endswith("\n") else body + "\n"


def parse_file_blocks(text: str) -> list[tuple[str, str]]:
    """Split on ### FILE: headers. A forgotten ``` must not eat the next file."""
    matches = list(HEADER_RE.finditer(text))
    pairs: list[tuple[str, str]] = []
    for i, m in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        pairs.append((m.group(1), text[m.end() : end]))
    return pairs


def strip_leaked_markers(root: Path) -> list[str]:
    """Truncate any source file that still contains Ralph ### FILE / END FILE lines."""
    cleaned: list[str] = []
    for p in root.rglob("*"):
        rel_parts = p.relative_to(root).parts
        if any(part in SKIP_DIR_NAMES or part == "scripts" for part in rel_parts):
            continue
        if not p.is_file() or p.suffix.lower() not in SOURCE_SUFFIXES:
            continue
        text = p.read_text(errors="replace")
        hit = MARKER_LINE_RE.search(text)
        if not hit:
            continue
        p.write_text(text[: hit.start()].rstrip() + "\n")
        cleaned.append(p.relative_to(root).as_posix())
        print(f"  stripped Ralph markers from {cleaned[-1]}", flush=True)
    return cleaned


def _block_complete(raw: str) -> bool:
    return bool(re.search(r"###\s*END FILE", raw) or re.search(r"\n```[ \t]*\Z", raw.strip()))


def write_files(text: str, dest: Path) -> list[str]:
    written: list[str] = []
    pairs = parse_file_blocks(text)
    if not pairs:
        pairs = list(FILE_RE.findall(text)) or list(FILE_RE_ALT.findall(text))
    last_idx = len(pairs) - 1
    for i, (path, content) in enumerate(pairs):
        if i == last_idx and not _block_complete(content):
            print(f"  skip incomplete last file {path}", flush=True)
            continue
        rel = safe_rel(path)
        if not rel:
            continue
        if ALLOWED_FILES and rel not in ALLOWED_FILES:
            print(f"  skip {rel}: not in story allowedFiles", flush=True)
            continue
        body = _clean_file_body(content)
        if not body.strip() or body.lstrip().startswith("### FILE:"):
            continue
        if _looks_like_planning(body):
            print(f"  skip {rel}: planning prose, not source", flush=True)
            continue
        if rel.endswith(".css") and body.count("{") != body.count("}"):
            print(f"  skip unbalanced css {rel}", flush=True)
            continue
        fp = dest / rel
        if rel.endswith(".css") and fp.exists() and len(body) < int(fp.stat().st_size * 0.85):
            print(f"  skip shorter css {rel} ({len(body)} < {fp.stat().st_size})", flush=True)
            continue
        if rel.endswith("globals.css") and fp.exists():
            old = fp.read_text(errors="replace")
            if old.count("{") == old.count("}") and old.count("{") > 0:
                last = LAST_VERIFY.read_text() if LAST_VERIFY.exists() else ""
                css_broken = "globals.css" in last and any(
                    s in last for s in ("Unknown word", "PostCSSSyntaxError", "Syntax error:")
                )
                if not css_broken:
                    print(
                        f"  skip valid existing css {rel}: LAST_VERIFY is not a CSS syntax error",
                        flush=True,
                    )
                    continue
        fp.parent.mkdir(parents=True, exist_ok=True)
        fp.write_text(body)
        written.append(rel)
        print(f"  wrote {rel} ({len(body)} bytes)", flush=True)
    strip_leaked_markers(dest)
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
    cmd = str(story["verify"]) if story.get("verify") else "true"
    strip = "python3 scripts/ralph/strip_markers.py"
    if "strip_markers.py" not in cmd:
        return f"{strip} && {cmd}"
    return cmd


def live_story(story: dict) -> dict:
    """Re-read PRD so a watchdog can enrich verify while this process is in chat()."""
    try:
        fresh = load_prd()
    except Exception:
        return story
    for item in fresh.get("userStories") or []:
        if item.get("id") == story.get("id"):
            return item
    return story


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
        "__pycache__/",
        "*.pyc",
    ]
    existing = gi.read_text() if gi.exists() else ""
    missing = [line for line in needed if line not in existing]
    if missing:
        extra = ("\n" if existing and not existing.endswith("\n") else "") + "\n".join(missing) + "\n"
        gi.write_text(existing + extra)


def commit(root: Path, story: dict) -> None:
    ensure_gitignore(root)
    stray = root / "gitignore"
    if stray.exists() and (root / ".gitignore").exists():
        stray.unlink()
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
    last = LAST_VERIFY.read_text() if LAST_VERIFY.exists() else ""
    files: list[Path] = []
    for p in sorted(root.rglob("*")):
        rel_parts = p.relative_to(root).parts
        if any(part in SKIP_DIR_NAMES or part == "scripts" for part in rel_parts):
            continue
        if not p.is_file() or p.suffix.lower() not in SOURCE_SUFFIXES:
            continue
        if p.name in {"package-lock.json", "pnpm-lock.yaml"}:
            continue
        files.append(p)
    # Files named in LAST_VERIFY first so a CSS/TS error is shown in full.
    def _prio(p: Path) -> tuple[int, str]:
        rel = p.relative_to(root).as_posix()
        return (0 if rel in last else 1, rel)

    chunks: list[str] = []
    total = 0
    omitted: list[str] = []
    for p in sorted(files, key=_prio):
        rel = p.relative_to(root).as_posix()
        if p.stat().st_size > 80_000:
            omitted.append(f"{rel} ({p.stat().st_size} bytes, too large)")
            continue
        text = p.read_text(errors="replace")
        if total + len(text) > 55_000:
            omitted.append(f"{rel} ({p.stat().st_size} bytes)")
            continue
        chunks.append(f"===== {rel} =====\n{text}")
        total += len(text)
    if omitted:
        chunks.append(
            "===== OMITTED (complete on disk — do not rewrite from memory) =====\n"
            + "\n".join(omitted)
        )
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
        "Close each ``` fence before ### END FILE. Never put ### FILE: or ### END FILE inside a file body.\n"
        "Do not rewrite a file unless this story or LAST_VERIFY requires it. Never emit a truncated CSS/TSX file.\n"
        "If a snapshot says OMITTED or you cannot finish a file, omit it — the on-disk copy stays.\n"
        "Do not draft ### FILE blocks in reasoning. Visible reply is the only write path.\n"
    )


def main() -> int:
    root = repo_root()
    ensure_gitignore(root)
    prd = load_prd()
    if all_passed(prd):
        print("<promise>COMPLETE</promise>")
        return 0
    story = next_story(prd)
    global ALLOWED_FILES
    ALLOWED_FILES = set(story.get("allowedFiles") or [])
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

    cmd = extract_verify_cmd(live_story(story))
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
