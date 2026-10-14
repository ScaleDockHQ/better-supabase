---
"better-supabase": minor
---

A `state-machine` machine can keep a lifecycle row per record with `lifecycle: true`: `pause(subjectType, id, { until, reason })`, `resume()` and `setFlag(subjectType, id, flag, enabled)` on `createStateMachine()`, a pinned `version` and a list of allowed `flags`. While a pause holds, the trigger refuses transitions with `STATE_PAUSED`; a pause with an end clears on the next transition after it. The module records `status.paused`, `status.resumed` and `status.flagged` next to `status.changed`.

The block reads as the caller: `state()` returns the status with its `step` and `progress` through the machine's new `order`, and the lifecycle; `history()` pages status changes newest first; `stages()` returns the stages timeline. `status_history`, `status_stages` and the new `subject_lifecycles` table have select policies that show a row when the caller can see its record. A machine without `table` takes its table, id type and tenant from `config.subjects`, and `idType` compares ids in their own type.
