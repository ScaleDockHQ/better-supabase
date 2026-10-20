---
"better-supabase": minor
---

Add `better-supabase run -- <cmd>`. It starts the command with the running stack's URL and keys set, over the shell's exported variables and every `.env` file, passes its output and exit code through, and forwards Ctrl+C and `SIGTERM`. When an exported `SUPABASE_*` variable differs from the stack, `run` warns and names it, showing the host and port of a URL or a `sha256:` fingerprint of a key, never the value.
