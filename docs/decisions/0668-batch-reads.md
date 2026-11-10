# 0668: Read run steps, versions, applications, templates and care plans in batches

- Status: accepted
- Date: 2026-11-10
- Amends: 0617, 0640

## Context

The performance audit listed five places where the example app read one row per call: the assistant
activity panel read the steps of each of 20 runs, the project history read every version it had just
listed, the hiring board listed the applications of each job, the templates gallery read each
template to get its published body, and the FHIR export read every care plan of a client. The calls
ran in parallel, so the wall time stayed low, but each page sent up to 100 requests where one would
do, and each request paid its own authorization check, connection and RLS setup. The block clients
had no batch method, so an app could not do better without its own SQL.

## Decision

Each block gets one function that takes a uuid array and answers what a loop of the per-row function
answers, with the same result shape.

| Block        | SQL function                                      | Client method                            |
| ------------ | ------------------------------------------------- | ---------------------------------------- |
| `ai-chat`    | `list_ai_run_steps_for(runs uuid[], per_run int)` | `runs.steps.listFor({ runIds, limit })`  |
| `versions`   | `get_versions(version_ids uuid[])`                | `getMany(ids)`                           |
| `hiring`     | `list_applications_for_jobs(jobs uuid[], state)`  | `applicationsForJobs({ jobIds, state })` |
| `templates`  | `templates_get_many(template_ids uuid[])`         | `getMany(ids)`                           |
| `care-plans` | `get_care_plans(plan_ids uuid[])`                 | `getMany(planIds)`                       |

**Result order.** Rows come back in the order of the ids (jobs in the order given, each in board
order; runs in id order with their steps in start order). Run steps come back as one flat
list, each step with its `runId`.

**Unreadable ids are skipped.** A single read raises `*_NOT_FOUND` or `*_FORBIDDEN`. A batch cannot
fail on one id without hiding the rest, so a missing id and an id the caller cannot read both have no
entry, and the caller compares lengths when it needs to tell. A member of another tenant gets `[]`.

**Checks run once per record, not once per row.** `get_versions` checks the tenant permission and
the subject once per distinct record, and `list_ai_run_steps_for` checks `ai_chat_can_read` once per
distinct chat, in a materialized CTE. `get_care_plans` filters on the plan visibility the single read
uses. `list_applications_for_jobs` and `templates_get_many` are `security invoker`, so the table
policies decide, as they do for the single reads. `get_versions` is PL/pgSQL because its inlined
subject check names tables of later modules (`tests/sql/registry.test.ts`).

**The example moved.** The assistant activity panel, the project history, the templates gallery, the people board
and the FHIR export call the batch methods in one request each.

## Scale numbers

`supabase/tests/scale/scale_batch_reads.test.sql` seeds a batch of 100 (50 jobs of 20 applications,
100 runs of 50 steps) next to 60,000 other rows on the native stack, prints `SCALE_MS` for a loop of
the single function and for the batch, and checks both answer the same ids in the same order. A loop
inside the database pays no network hop, so these numbers understate what an app saves: the loop
column plus one round trip per row is what the old call sites paid. Three runs, milliseconds:

| Read                                 | Loop in SQL (per-row calls) | Batch, one call | Requests before, after |
| ------------------------------------ | --------------------------- | --------------- | ---------------------- |
| versions, 100 with content           | 47 to 57                    | 2               | 100, 1                 |
| templates, 100 with published bodies | 128 to 130                  | 3               | 100, 1                 |
| applications, 50 jobs, 1,000 rows    | 21 to 24                    | 6               | 50, 1                  |
| care plans, 100 with a tree each     | 54 to 55                    | 49 to 50        | 100, 1                 |
| run steps, 100 runs, 5,000 steps     | 18 to 24                    | 22 to 24        | 100, 1                 |

Care plans and run steps are bound by building the JSON of the rows (5,000 steps, 100 plan trees),
so the batch saves the requests and the repeated authorization, not database time. The speedups for
versions and templates come from one index scan replacing 100 separate plans and from checking the
subject once.

## Alternatives considered

- Wrap the single functions in an invoker function that loops: no new definer functions, but it keeps
  the per-row checks and plans, which is where the time goes for versions and templates.
- Fail the whole batch on one unreadable id: simpler to reason about, but one stale id in a list
  would blank a page.
- One generic `get_many(entity, ids)`: it would need dynamic SQL per entity and could not use the
  per-block checks.

## Consequences

`security-definer-functions` in `tests/sql/practices-baseline.json` rises by six for `ai-chat`,
`care-plans` and `versions` (one function times six rendered variants each). These three need the
caller checks inside the function, so they cannot be invokers; the rule says definer counts go down,
and this is a deliberate exception, recorded here. `hiring` and `templates` stay invokers.

The server bundle grows. The five client methods add about 617 bytes of raw JavaScript to each
server route that carries the block set (measured against a build of main at the same commit: 97
routes +617, 21 routes +623, 8 routes +121, 37 routes unchanged; gzip between -214 and +213 bytes,
brotli between -19 and +236). Each method is a call with its argument map and a result mapper,
about 110 to 150 minified bytes, and the string name of the function appears once per method.
`tests/next-build/next-build.test.ts` fails on "never grows past the server baseline" for 132
routes by 310 to 379 raw bytes beyond the 512-byte slack (gzip and brotli stay inside theirs),
because main had less than 300 bytes of headroom left. This change does not edit the test or the
baselines. A maintainer either raises the server baseline by about 620 bytes raw or asks for some of
the reads to go; the methods are already reduced to a call and a mapper each (the run steps method
returns a flat list instead of grouping, and `templates` shares one detail mapper with `get`).

No new events, permissions or tables. The migration only adds five functions and their grants.
