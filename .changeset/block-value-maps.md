---
"better-supabase": minor
---

Blocks take `blocks.<name>.values.<table>.<column>`, which maps each label a block writes or compares to the value your own column stores: `{ cancelled: "canceled" }`, several values for one label (`{ started: ["in_progress", "on_hold"] }`, the first is written), or `null` for a label the app does not support, which fails with `VALUE_UNSUPPORTED`. The map applies to writes, comparisons in functions, triggers and pipeline bindings, and to the typed fields read functions return. Tasks (`state`, `closeReason`, and `priority` once mapped), calendar (`status`, and `kind`, `transparency`, attendee `role` and `response` once mapped), employees (`status`) and hiring (`state`, job `status`) apply it. A config without `values` renders the same SQL as before.
