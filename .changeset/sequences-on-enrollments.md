---
"better-supabase": minor
---

Sequence runs are now enrollments (ADR 0131). Each run is a row in `enrollments` whose `program` is `sequence:<sequence id>`, and the `sequence_enrollments` table is gone. The run's own columns move onto `enrollments` with a `sequence_` prefix (`sequence_id`, `sequence_address`, `sequence_mail_thread_id` and the rest), the next step is the run's open `enrollment_steps` row with `due_at`, a paused run has the new `paused_at` column, and an exited run is `cancelled` with the reason in the new `cancel_reason` column. `upgrade` renders a data step that copies each `sequence_enrollments` row onto its enrollment and next step, then drops the table. The sequences client keeps its methods and the run shape it returns.

```sql
-- Before
select address, status, step, next_run_at
from better_supabase.sequence_enrollments
where sequence_id = $1;

-- After
select x.sequence_address, x.status, x.paused_at, x.cancel_reason, s.step, s.due_at
from better_supabase.enrollments x
left join better_supabase.enrollment_steps s
  on s.enrollment_id = x.id and s.completed_at is null
where x.sequence_id = $1;
```

Run events are the enrollment events, with `program` in the payload. The enrollments block adds `enrollment.paused` and `enrollment.resumed`, and `enrollment.cancelled` carries an optional `reason`.

| Before                                                 | After                                                    |
| ------------------------------------------------------ | -------------------------------------------------------- |
| `sequence_enrollment.created`, `.step_completed`       | `enrollment.created`, `.step_completed`                  |
| `sequence_enrollment.paused`, `.resumed`, `.completed` | `enrollment.paused`, `.resumed`, `.completed`            |
| `sequence_enrollment.exited`                           | `enrollment.cancelled`, with the exit reason in `reason` |

```ts
// Before
await outbox.register("crm", { types: ["sequence_enrollment.completed"] });

// After: other programs emit enrollment.completed too, so check data.program
await outbox.register("crm", { types: ["enrollment.completed"] });
```

`better-supabase codemod 0.47` lists the old types for review, doctor reports them (BS424) and `sequence_enrollments` in your code, and the stored-type data step renames them in the outbox, automations and timeline. Until 0.48, the outbox `legacyEventTypes` option relays a sequence run event under its old name, `legacyEventType(type, data)` returns it for a payload whose `program` starts with `sequence:`, and `SequenceEnrollmentEventData` is a deprecated alias of `EnrollmentEventData`. `PROGRAM_EVENT_MOVES` (`better-supabase`) lists the moves.
