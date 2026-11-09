---
"better-supabase": minor
---

The tenant table can be a record type: set `recordTypes.<type>.tenant` to its id column, and each organization is its own tenant. The consents block then records a decision on the organization itself, such as an agreement it accepts, and a member can only record one for their own organization. `gen` no longer marks such a table as tenant-scoped, so the client keeps reading every organization the caller belongs to.
