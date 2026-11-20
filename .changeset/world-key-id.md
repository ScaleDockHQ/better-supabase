---
"better-supabase": minor
---

The Supabase World stamps the id of the encryption key on each new run when the key ring has more than one key. The id is the run attribute `$bsb.key_id`, and a run keeps opening with its key when a `from` date in the ring changes. Runs created before the ring had a second key still match by date.
