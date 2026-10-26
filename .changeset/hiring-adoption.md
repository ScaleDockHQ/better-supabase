---
"better-supabase": minor
---

The hiring block runs over an applicant tracker's own tables. `columns.applications.candidateType: null` makes every candidate an `options.candidate` record and writes the id as the column's own type, such as a uuid foreign key. `options.stages` takes the app's table of stages per job, with boolean or keyed markers for hired, rejected and withdrawn stages, so the job is the pipeline and `applications.pipeline` can be `null`. `tables.interviewers` keeps interviewers as junction rows, `options.scorecardKey: "application"` keeps one scorecard per reviewer per application, `scorecards.recommendation` can be `null`, and `tables.scorecardScores` stores criterion scores that `score({ scores })` writes and `detail` returns. `options.hiringManager: "employee"` takes an employee id, and `employmentType`, `source` and interview `kind` accept value maps. A config without the new keys renders the same SQL.
