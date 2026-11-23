# 1218: A policy costs its predicate, so bsb_session_active stays its own policy

- Status: accepted
- Date: 2026-11-23

## Context

An adopter's `tasks` table had 13 policies, and the scale report asked whether
the library should merge its restrictive policies. A tenant table carries nine
library policies: one permissive and one restrictive tenant scope per command
(ADR 0104), and `bsb_session_active`, restrictive for all commands. The plan
was to fold `bsb_session_active` into the tenant scope policies if that saved 5
percent or more on a 1,000-row list read, and otherwise to ship only the doctor
rule of ADR 1216.

## Measured

`supabase/tests/scale/scale_policy_count.test.sql` reads 1,000 rows of one
tenant as a member, serialized the way PostgREST does, 50 times per set, on
the local stack (Postgres 17.6). Median of five runs, mean per read:

| Policies                                                    | Read (ms) |
| ----------------------------------------------------------- | --------- |
| 9: the library's set                                        | 0.92      |
| 8: without `bsb_session_active`                             | 0.90      |
| 8: `session_active()` folded into the select tenant scope   | 0.98      |
| 13: the 9 plus two permissive and two restrictive app rules | 1.00      |

Dropping `bsb_session_active` saves 0.02 ms, which is its one indexed session
lookup per statement: the policy wraps the call in a select, so Postgres runs
it once, not per row. Folding the call into the tenant scope keeps that lookup
and was 6 percent slower in this run, within noise of the library's set. The
four extra policies add 0.08 ms (9 percent), and that time is in their own
predicates, which a merge would still evaluate.

## Decision

No fold. `bsb_session_active` stays one restrictive policy per table, so a table
without tenant scope and a table with it get the same session check, and
`config policies` and BS207, BS347 and BS375 keep reading one policy. Doctor
BS641 (ADR 1216) stays the answer to a long policy list: it names the owner of
each policy, and the owner can drop or merge its own.

The plan's optional provider guard predicate, which the library would render
inside its own guard, is not added: the measurement shows the cost is in what a
predicate does, not in how many policies hold it.

## Consequences

None for apps. The scale test stays in `supabase/tests/scale` so a later
Postgres or library change can be measured again.
