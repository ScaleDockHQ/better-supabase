---
"better-supabase": minor
---

The `hiring` SQL module and `better-supabase/blocks/hiring` add an applicant tracking system on pipelines. Installing hiring binds the `application` type in the pipelines module with one pipeline per job (Applied, Screening, Interview, Offer, then Hired, Rejected or Withdrawn). Jobs open and close, a candidate is any record in `config.subjects` (a person by default) and applies once per job, and interviewers score the application at its current stage. `hire`, `reject` and `withdraw` end an application, and `application.hired` carries the candidate for the app to turn into an employee.
