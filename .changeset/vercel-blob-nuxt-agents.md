---
"better-supabase": minor
---

Blob client uploads, Nitro 3 in the Nuxt module and an agent block from `init`. There are no breaking changes.

## Features

- `blobUploadRoute` (`better-supabase/storage`) answers Vercel Blob client uploads: `authorize` runs your permission check before a token is issued, and `onCompleted` records the finished upload.
- The Nuxt module detects Nitro 2 or 3 and writes `toH3V1` or `toH3` middleware to match.
- `better-supabase init` writes a managed block into `AGENTS.md` for projects that already have agent files.
