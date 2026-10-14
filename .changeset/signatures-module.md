---
"better-supabase": minor
---

Add the `signatures` SQL module and `createSignatures` in `better-supabase/blocks/forms`: simple electronic signatures on a frozen version of a record, signed by click, typed name or drawn image, in parallel or in order. Each signature stores a hash over the version's content, so `get` reports whether the signed content or a signature changed and whether the record has a newer version. With the approvals module, a signer's signature can approve the step of a linked approval request.
