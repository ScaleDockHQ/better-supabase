---
"better-supabase": minor
---

Add the `enrollments` block: enroll a party, member or any record in a program of steps, and track its progress and completion.

- `better-supabase add enrollments` installs programs per organization. A program has ordered steps and the subject types it enrolls. Saving changed steps raises the program's version, and enrolling again picks up the new steps while keeping the completed ones.
- `createEnrollments` from `better-supabase/blocks/enrollments` saves programs, enrolls subjects, completes and resets steps, cancels enrollments and lists them by program, subject or status. Changes emit `enrollment.created`, `enrollment.step_completed`, `enrollment.completed` and `enrollment.cancelled`, and `enrollmentsSection` shows a record's enrollments on its page (ADR 0077).
- New permissions: `enrollments.read`, `enrollments.enroll` and `enrollments.manage`.
