---
"better-supabase": minor
---

`people.onboard` and the new `employees.onboardWithProgram` run as one database call. The `onboard_with_program` function creates the employee, enrolls them and sets the enrollment dates in one transaction, so a failed enrollment now rolls the employee back instead of leaving them created. The TypeScript hooks of `employees.create` and `enrollments.enroll` no longer fire inside `people.onboard`; the composite's own hook does.
