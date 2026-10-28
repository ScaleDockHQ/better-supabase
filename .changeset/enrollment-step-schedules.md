---
"better-supabase": minor
---

Enrollment program steps take an `assignee` (`{ role }` or `{ userId }`) and a `due` date (`{ days, from: "start" | "end" }`). Enrollments gain `startsAt` and `endsAt`, set through `enroll(program, subject, dates)` or the new `setDates`, and each scheduled step gets an open `enrollment_steps` row with its rendered `due_at`. `openSteps()` lists the open steps by due date, an assigned user can complete their step, and an enrollment's `schedule` lists its scheduled steps. Run `better-supabase upgrade` and `db diff` to add the columns; rows in `enrollment_steps` with a null `completed_at` are open steps, so filter on `completed_at` in your own queries over the table.
