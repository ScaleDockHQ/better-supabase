---
"better-supabase": patch
---

Doctor BS502 asks `git check-ignore` whether an env file with secrets is ignored, so `.git/info/exclude`, the global excludes and `!` negations count, and a committed env file is reported even when a pattern matches it. Outside a git work tree it reads each `.gitignore` from the app up to the repository root against paths relative to its own folder, with negations, instead of matching every pattern against the app's paths.
