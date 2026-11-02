---
"better-supabase": minor
---

Every port an app plugs in now needs `apiVersion: 1`. The prescription gateway, the clinical decision
support engine and the funding claim format and channel used to accept a missing `apiVersion`; add
`apiVersion: 1` to yours. All ports now share one check, `portOf`, so the error for a wrong version reads
the same everywhere.
