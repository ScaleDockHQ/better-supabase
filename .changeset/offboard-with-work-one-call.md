---
"better-supabase": minor
---

`people.offboard` without id lists, and the new `employees.offboardWithWork`, run as one database call. The `offboard_with_work` function offboards the employee, cancels their active enrollments and unassigns their open shifts in one transaction. The parts' TypeScript hooks (`employees.offboard`, `enrollments.cancel`, `shifts.unassign`) no longer fire on that path; the composite's own hook does. `invite_within_seats` now runs with the caller's rights.
