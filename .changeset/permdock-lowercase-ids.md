---
'better-supabase': patch
---

The storage and realtime docs say that the `permdock` policy mode compares ids as text, so a path or topic segment must be the id's canonical lowercase form: an uppercase uuid is denied. An integration test covers it for buckets and topics.
