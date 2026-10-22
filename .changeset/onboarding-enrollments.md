---
"better-supabase": minor
---

Breaking: onboarding checklists run on the enrollments block.

- The onboarding block now requires `enrollments`. Each checklist is the program `onboarding:<checklist>`, with the organization or the user enrolled in it.
- `better-supabase sql upgrade` moves the rows of `onboarding_progress` into enrollments and their completed steps, then drops the table. `createOnboarding`, `useOnboarding` and the onboarding functions keep their signatures.
- Queries on `onboarding_progress` read `enrollment_steps` joined to `enrollments` instead. See the 0.13 to 0.14 guide.
