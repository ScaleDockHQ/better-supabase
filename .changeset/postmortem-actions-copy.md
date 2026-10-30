---
"better-supabase": patch
---

The incidents module copies existing postmortem `action_items` into tasks. With `tasks` installed,
`better-supabase add --adopt` writes a data step that calls `add_incident_postmortem_action` for
each item, keeps the `action_items` column readable and skips a postmortem that already has linked
actions, so it is safe to run again.
