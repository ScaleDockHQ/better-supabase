---
"better-supabase": patch
---

`better-supabase codemod` skips a folder that holds its own `.git`, such as a
linked git worktree inside the project, so it no longer rewrites another
checkout's files.
