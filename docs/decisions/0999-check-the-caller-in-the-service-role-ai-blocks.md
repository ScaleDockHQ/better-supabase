# 0999: Check the caller in the service-role AI blocks

- Status: accepted
- Date: 2026-11-14

## Context

`prompts`, `ai-evals` and `ai-guardrails` run as the service role, because
templates, items and the decision log can hold instructions and user content.
The service role bypasses row-level security, so the blocks themselves decided
nothing about who was asking. The example (finding EX-301) kept the check in
one helper, `opsTenant`, that every read called first. A page, action or job
that forgot it read another organization's rows, and the id-based eval calls
(`items.add`, `runs.results`, `runs.compare`) accepted any dataset or run id
whatever organization it belonged to.

The blocks are in category `ai`, which audit lane G5 still has to cover, so
this change is kept additive and small.

## Decision

Each of the three blocks takes an optional `access: AiAccess`
(`src/blocks/ai-access.ts`): the caller's `organizationId`, whether the caller
holds the permission the app requires, and the permission key for the error.

- Every method returns `forbidden` before it reaches the database when the
  caller has no organization or lacks the permission.
- A call that names an organization (`organizationId`) must name the caller's.
  A system record (no organization) is refused too, so a caller cannot write a
  system prompt or policy.
- `ai-evals` resolves the organization of every dataset and run a call names
  and answers `not_found` for another organization's, so a foreign id does not
  confirm it exists. That needs a read of one dataset, so the module gains
  `get_eval_dataset(dataset)` and `datasets.get`, written by `upgrade` and
  shipped in the migration `20270107120000_ai_eval_get_dataset.sql`.
- `ai-guardrails` refuses `decisions.purge`, which deletes across
  organizations, and an unscoped `decisions.list`.

Without `access` the blocks behave as before, so a background job and the
assistant's runtime keep an unscoped client. The example passes `access` from
the session on every ops page and from the action context on every action,
and `opsTenant` is gone.

## Alternatives considered

- Check inside the SQL functions with a `caller` argument: it would change all
  three modules, every signature and the generated SQL of each install, for a
  check the TypeScript wrapper does with one more read. It also does not
  help a caller that already holds the service role.
- Require `access` and drop the unscoped mode: it breaks the runtime that
  guards a chat turn and every existing app in a patch release.
- Leave the check to `hooks.before`: it works, but every app writes it again,
  and the id-based eval calls need the dataset lookup the block can do once.

## Consequences

A signed-in caller can no longer reach another organization's records through
these blocks by passing an app-side mistake through. The unscoped mode stays a
trust-the-caller default, documented on each block page. Audit lane G5 can
move the check into the SQL contract when it reviews the `ai` category, and
this ADR is the record of what the wrapper does until then.
