---
"better-supabase": minor
---

The CLI has an agent mode. When a coding agent runs it (Cursor, Claude Code, Codex, Gemini CLI, GitHub Copilot and the others `@vercel/detect-agent` knows), it prints the JSON result envelope by default, never prompts, and answers what it can't decide alone with exit code 3 and `status: "action_required"`. `--agent auto|yes|no` and `$BETTER_SUPABASE_AGENT` override the detection, and `--no-json` keeps text output.

A missing value returns `input_required` with `missing`, `choices` and a `next` command that fills them in. Destructive work returns `consent_required` with a `token`: `--force` over files the CLI didn't write, and `seed --apply` against a database that isn't on this machine. Rerun with `--confirm <token>` once the user agrees; `--yes` doesn't replace it.

`init` at a workspace root without `--package` now exits 3 with `input_required` instead of 2, and `skills install --agent` is now `skills install --for`, so the global `--agent` keeps one meaning.
