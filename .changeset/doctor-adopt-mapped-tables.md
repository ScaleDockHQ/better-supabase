---
"better-supabase": patch
---

Doctor BS330 no longer reports an adopted module's opt-in tables that `blocks.<name>.tables` does not map: the notifications `deliveryEvents` and `suppressions`, the audit `restricted` table and the invitations `platformInvitations`. The generated SQL uses those tables only when they are mapped, so the check now matches it and still reads a mapped table's columns. `ModuleTableSpec` gains `adoptOnlyWhenMapped` to mark such a table.
