---
"better-supabase": minor
---

Generated triggers are named `bsb_*`, unique constraints end in `_key` and exclusion constraints in `_excl`. Run `better-supabase codemod naming` to write the migration that renames them in an installed app; no data moves.

| Old                                                                                                                                                                                                                               | New                                        |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| triggers `conversations_broadcast`, `inbox_conversation_events_broadcast`, `inbox_message_deliveries_broadcast`, `bookings_engagement`, `passes_credit_refund`, `calendar_attendees_auto_decline`, `calendar_events_auto_decline` | the same names with a `bsb_` prefix        |
| indexes `bsb_rate_limit_rules_scope_global`, `bsb_rate_limit_rules_scope_org`                                                                                                                                                     | the same names ending in `_key`            |
| constraints `flag_overrides_unique`, `flag_revisions_unique`                                                                                                                                                                      | `flag_overrides_key`, `flag_revisions_key` |
| constraints `<table>_no_overlap` (bookings, time entries, shift assignments, leases, passes, calendar events)                                                                                                                     | `<table>_no_overlap_excl`                  |
