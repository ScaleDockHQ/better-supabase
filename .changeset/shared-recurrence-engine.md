---
"better-supabase": minor
---

Recurrence rules expand in one place. The new `better-supabase/recurrence` entry exports
`expandRule` and `rruleOccurrences`, and the new `recurrence` SQL module adds
`better_supabase.rrule_occurrences` and `rrule_next`, which return the same instants. The
calendar block's `calendar_rule_starts` now wraps it, and the templates block gains
`due_template_occurrences`. Run `better-supabase upgrade` to install the module.
