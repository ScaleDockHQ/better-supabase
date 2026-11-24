---
"better-supabase": patch
---

`doctor` parses each TypeScript source once for all rules and runs the rules together, which takes
a doctor run on the CRM validation project from 16.9 s to 14.5 s. Findings keep their order.
