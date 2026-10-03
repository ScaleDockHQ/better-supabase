---
"better-supabase": patch
---

PermDock's catalog is read fail closed. `defineBucket` and `defineTopic` with `catalog` accept only keys marked `rowConditions: false`: a key whose entry has no boolean `rowConditions`, or that the catalog doesn't list, now throws with a message to regenerate the catalog with a current `permdock catalog`. Doctor BS214 reports those keys as errors, and `better-supabase gen` refuses to write their bucket policies.
