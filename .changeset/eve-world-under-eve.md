---
"better-supabase": minor
---

Make the Supabase World work under eve and behind the transaction pooler.

- `connection: "transaction"` (chosen on port 6543, or with `WORKFLOW_POSTGRES_CONNECTION`) polls stream readers and omits the `LISTEN` based run status and event feeds, so the World no longer warns on the pooler. The warning now appears only for `connection: "session"` on a pooled URL.
- The stream flush interval defaults to 20 ms. The pool holds 2 connections by default on Vercel, AWS Lambda and Netlify.
- `encryptionKeys` (`WORKFLOW_ENCRYPTION_KEYS`, Vault secret `workflow_encryption_keys`) takes a ring of master keys for rotation, and `world.start()` warns when no key is set outside development and test.
- New exports from `better-supabase/workflow-sdk/world`: `isServerless`, `parseKeyRing`, `ringKeyFor`, `runCreatedAt`, `RingKey`, `WorldConnection`.
