---
"better-supabase": minor
---

Add the `controls` block (`better-supabase/blocks/controls`). It keeps compliance frameworks and their controls, evidence linked to a control (an attachment or a note, valid until a date), and recurring evidence tasks with an assignee and an overdue state that `notifyOverdue()` reports once per lapse. A control's status (passing, failing, not started or not applicable) is computed from its evidence and tasks and rolled up per framework. Policies are published as versions, and members acknowledge each one. Install it with `better-supabase add controls`; it needs `versions`.
