---
"better-supabase": minor
---

Give signatures their own block at `better-supabase/blocks/signatures`. The SQL module, its tables and `blocks.signatures` stay the same, so only imports change. See [Signatures](https://bettersupabase.com/docs/blocks/signatures) and [From 0.13 to 0.14](https://bettersupabase.com/docs/migration/0.13-to-0.14#signatures-get-their-own-block).

| Before (`better-supabase/blocks/forms`) | After (`better-supabase/blocks/signatures`) |
| --------------------------------------- | ------------------------------------------- |
| `createSignatures` and its types        | `createSignatures` and its types            |
| `signaturesBlock`                       | `signaturesBlock`                           |
| `signaturesEvents`, `SignaturesEvents`  | `signaturesEvents`, `SignaturesEvents`      |
