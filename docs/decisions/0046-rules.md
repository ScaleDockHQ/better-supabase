# 0046: Store tenant rules as filter trees with action references

- Status: accepted, amended by 0093 (one action registry: `defineAction`, `createActionRegistry`)
- Date: 2026-10-19

## Context

Apps keep asking for the same screen: "when an expense is submitted and the
amount is over 500 and the merchant is Uber, ask the finance team". Approvals
picks a policy per subject type and action, workflow-builder has a condition
node with one `{ path, op, value }` test, notifications and webhooks-out
filter by event type only, and forms have their own `showIf`. Each of them
would grow its own condition language, its own editor and its own checks.

The list tooling already has one: the `FilterQuery` tree (groups of rules
with `and` or `or`), its operator table per field type, `checkFilterQuery`,
`filterWhere` for SQL and, since this change, `evaluateFilterQuery` for one
record in memory. ReUI's Filters component edits the same tree.

## Decision

The `rules` block stores tenant-editable rules. A rule names a subject type
and a trigger (an event type such as `expense.submitted`), holds a
`FilterQuery` in `conditions` and a list of actions in `actions`, and has a
rank key (ADR 0021), an enabled flag, `stop_processing` and a version. Every
save writes a row to `rule_versions`, and `record_rule_evaluation` keeps a
log of live and test runs in `rule_evaluations`.

Fields come from a catalog per subject type, `rule_fields`, that the app
declares in code with `defineRuleFields` and syncs with the service role,
the way workflow-builder syncs its step library. A field names its type, its
record key (dotted for nested values), its Postgres type and its options, so
the same entry feeds the editor (`toFilterFields`), the TypeScript evaluator
and the SQL one. `save_rule` checks the tree against the catalog and the
operator table, which the module renders from `FILTER_OPERATORS`.

Actions are references, `{ kind, config }`, never code. The rules client
returns the matches, and `createRuleDispatcher` runs the app's handler for
each kind; a missing handler is an error result, not a throw. The block owns
no side effect, so a handler can't change what matched (invariant 5).

Evaluation runs in both places. `evaluateFilterQuery` runs in the client and
in the dispatcher; `rule_matches` and `rule_evaluate` in plpgsql run inside
database functions and triggers. A parity test runs the same cases through
both, and `evaluateFilterQuery` has its own parity test against
`filterWhere`.

Permissions are `rules.read` (rules and the evaluation log), `rules.edit`
(create rules and change disabled ones), `rules.publish` (enable, disable,
and change enabled rules) and `rules.admin` (remove rules). Admins hold
`rules.*` and members `rules.read` by default.

## Alternatives considered

- **A rule language as text (CEL, JSONLogic).** It needs a parser in two
  languages and an editor of its own, and ReUI's Filters can't edit it.
- **Pluggable action classes with an `apiVersion`.** A handler map keyed by
  kind does the same job, keeps the block free of SDKs and needs no contract
  beyond `{ kind, config }`. A versioned interface is the step up if
  handlers ever need to describe their config to the editor.
- **Evaluation in TypeScript only.** Triggers and security definer functions
  could not use rules, so approvals and SLAs would need a round trip.
- **Fields from `config.subjects` columns only.** Rules test values that
  aren't columns (the submitter's seniority, a computed total), so the
  catalog names record keys instead of columns.

## Consequences

Approvals, workflow-builder, notifications, webhooks-out, pipelines and SLAs
can take a rule id or a `FilterQuery` instead of growing their own
conditions; approvals and workflow-builder adopt it first. Two evaluators
must stay in step, which the parity test enforces. Revisit the action
contract when an action needs typed config in the editor.
