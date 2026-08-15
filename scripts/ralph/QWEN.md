# Ralph Agent Instructions (Studio Qwen)

You are a **fresh** coding agent. You have no memory of prior turns except:
- `prd.json`
- `progress.txt` (read Codebase Patterns first)
- git history
- `LAST_VERIFY.txt` if present (previous iteration's failed check)

## Task

1. Pick the **highest priority** story in `prd.json` where `passes` is false.
2. Implement **only that story**.
3. Emit complete files as:

### FILE: relative/path
```
full file
```
### END FILE

4. After files, write exactly one of:
   - `VERIFY: <shell command to prove this story>`  (required)
   - If you believe every story in the PRD now passes: `<promise>COMPLETE</promise>`

## Rules

- One story per iteration. Do not "also fix" other stories.
- Stories must be small enough for one context window.
- No placeholders, no omitted code, no `// rest here`.
- Do not touch clipfarm, `lmstudio-ensure`, or `com.clipper.*`.
- Do not invent acceptance. Use the story's `acceptanceCriteria`.
- Frontend stories: VERIFY must include an HTTP check (`curl -sS -o /dev/null -w "%{http_code}" ...`) not just "files exist".
- iOS stories: VERIFY must include `xcodebuild`.
- If LAST_VERIFY.txt exists, fix **that failure** for the current story. Do not ignore it.
