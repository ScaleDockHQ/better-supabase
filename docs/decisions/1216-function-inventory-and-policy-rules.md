# 1216: Function inventory and policy rules in doctor

- Status: accepted
- Date: 2026-11-23

## Context

An adopter's `tasks` table had 13 policies for one command, and 12 of them came
from the authorization provider or the app. Postgres evaluates every
permissive policy and every restrictive one on each row, and nothing in doctor
said which policies were there or who owned them. The same report asked whether
an index on an enum status column is used under RLS: `enum_eq` is not
leakproof, so the planner can refuse to push a filter on it below a policy's
quals. On the local stack (Postgres 17.6) `enum_eq` is not leakproof, while
`texteq`, `int4eq` and `uuid_eq` are. The adopter also could not tell which of
the more than 3,000 functions in the `better_supabase` schema their app called.

ADR 0460 left a pgTAP `explain` test for list reads under RLS undone.

## Decision

Doctor gains three information rules:

- BS641 counts the policies that apply to `authenticated` per table and
  command and reports any count above `doctor.policies.max` (default 4). Each
  policy is listed with its kind (permissive or restrictive) and its origin:
  library (the `bsb_` prefix or a block-owned table), provider (its quals call a
  provider function) or app.
- BS642 reports an exposed table with RLS whose index leads with an enum
  column, and recommends `text` with a check constraint, which every block
  already uses. The library ships no leakproof helper, because marking a
  function `leakproof` needs a superuser.
- BS643 prints, per schema, how many functions are referenced by a policy, by a
  trigger, callable by the app (`execute` for `anon` or `authenticated`),
  callable only by `service_role`, or unreferenced.

The inventory behind BS643 is part of the introspected snapshot
(`functionInventory`) and is listed by the new `config functions` command, which
prints the counts or, with `--all`, every function with its caller class.
`listFunctions` in `better-supabase/sql` assigns the class. Nothing is dropped.

`supabase/tests/database/list_plans_under_rls.test.sql` runs a status-filtered
orders list and invoices list as `authenticated` with claims set and asserts an
index scan with the status in the index condition, which closes that line of
ADR 0460.

## Alternatives considered

A warning instead of information for BS641. Most policies over the limit come
from the provider or the app, which the library cannot change, and the cost per
policy is the subject of a separate measurement.

Shipping a leakproof equality for enums. It needs a superuser, which a hosted
project does not grant, and `text` with a check needs no such function.

## Consequences

Apps see who owns each policy before they decide which to merge, and a list of
functions they never call. The snapshot schema gains an optional field, so
older snapshots still load; `config functions` asks for a fresh one.
