---
"better-supabase": minor
---

The block render cache now keys on a hash of the generator's files as well as the version, so a checkout or a rebuilt `dist` never serves output an older generator wrote.
