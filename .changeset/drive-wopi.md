---
"better-supabase": minor
---

`better-supabase/blocks/drive` exports `createWopiHost`, a WOPI host for
drive files: `CheckFileInfo`, `GetFile`, `PutFile` and the lock calls run on
the check-out lock, behind signed access tokens.
