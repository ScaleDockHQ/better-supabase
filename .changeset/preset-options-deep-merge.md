---
"better-supabase": patch
---

A preset's block options now merge key by key with the options you set on the same block in
`defineConfig`, so `blocks: { attachments: { options: { requireScan: true } } }` keeps the preset's
`publicBuckets` instead of replacing the whole `options` object.
