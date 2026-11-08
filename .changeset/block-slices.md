---
"better-supabase": minor
---

`gen.blockModules: true` writes `blocks/slices.ts`, one config slice per installed block instance (`commentsConfig`), and `blocks/permissions.ts` with the permission keys. `blocks.config.ts` composes `blockConfig` from the slices for server code, and a generated record file imports only the slices of the blocks it binds instead of `blockConfig`. A client passes the slices it uses to `createClient({ blocks })`, and a record's own slices fill in the blocks the client leaves out. Run `better-supabase gen` to write the files.
