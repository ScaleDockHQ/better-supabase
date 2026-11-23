---
"better-supabase": minor
---

Add `authorization.doctor.timeoutMs` (60000 by default). A provider doctor command that runs longer is stopped and reported as a BS705 finding that names the setting. `doctor --update-baseline` no longer gives a new BS705 entry the reason of an entry with another provider code.
