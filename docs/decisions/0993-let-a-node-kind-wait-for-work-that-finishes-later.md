# 0993: Let a node kind wait for work that finishes later

- Status: accepted
- Date: 2026-11-14

## Context

A custom node ran as one step: `human-task` only notified the member and the
run went on, and `sub-workflow` started the child without waiting for its
result (finding EX-203).

## Decision

`defineNodeKind` accepts `waits: true`. For such a node the engine registers a
hook named `nodeWaitToken(runKey, node)` before the node's step (so a resume
during the step is not missed), calls the node, awaits the hook, then calls the
node a second time with `call.resumed = { payload, output }`; the second call
returns the node's final output. `GraphRuntime.waitFor` registers the hook for
`executeGraph`, and `compileGraph` emits the same calls for dynamic workflows.
A test run returns the stub and never waits. `nodeRunReporter` takes
`{ waits: true }` to record `waiting` instead of `completed` on the first
call. The example's human task waits for `completeHumanTask`, a server action
that checks the run's organization and the assignee, and its sub-workflow waits
for an outbox consumer that wakes the parent when the child's run ends, using
the child key `sub:<parent key>:<node>`.

## Alternatives considered

A dedicated wait that the app runs after the step: it could miss a resume that
arrives during the step. A new built-in node kind: the engine would need to
know about tasks and child runs, which only the app does.

## Consequences

A waiting kind is called twice per run, so its first call must be idempotent.
The resume code needs the run's key, which the run record keeps. Kinds that do
not set `waits` run as before.
