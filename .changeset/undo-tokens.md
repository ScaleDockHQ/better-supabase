---
"better-supabase": minor
---

New `better-supabase/blocks/undo` applies the undo tokens that `relations.link`, `relations.unlink` and `audit.revert` return, checking that every call is an accepted inverse, and `better-supabase/blocks/undo/react` adds `useUndoStack`, a stack of tokens for a toast's Undo button or a Cmd+Z handler.
