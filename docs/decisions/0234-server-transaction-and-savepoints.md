# 0234: Run repositories and blocks in one server transaction

- Status: accepted
- Date: 2026-11-05

## Context

Apps that append to a legal or financial trail need several steps to commit
together: a fact, a signed document version, an approval and an audit event.
`postgres.transaction` already gave that, but the app had to rebuild a `Db`
over the transaction client with its claims and tenant, nothing rolled back
when a step returned an error `Result`, and a nested `tx.transaction` was
flattened, so one failed statement aborted the whole transaction (SQLSTATE
25P02).

## Decision

`server.transaction(userId, fn, options)` opens one transaction as the user
through the optional `BetterPostgres.transactionFor`, and passes `fn` a `Db`
bound to it. Repository writes and every block on that `Db` share the
transaction, because blocks run through `dbTransport(db)`. A throw rolls back,
and so does a returned `Result` that is not ok; the `Result` is still
returned.

A nested `SqlClient.transaction` inside a transaction now runs in a
savepoint, released on success and rolled back alone on error. `Executor.batch`
and the row-and-count reads use it, so they recover inside a transaction.

`transactionFor` is optional on `BetterPostgres`, so custom implementations
keep working; `server.transaction` fails with a clear message without it.

## Alternatives considered

- A `ctx.transaction` on every context kind. The context is built in several
  places (request, API key, support session); the server method covers jobs,
  webhooks and handlers that know the user, and can be added to the contexts
  later without a contract change.
- Leaving nested transactions flat. It makes every step all or nothing and
  hides which step failed.

## Consequences

Multi-step commands are written in TypeScript with the database enforcing the
rules. Each nested transaction costs two extra statements. `rpcTransport`
and PostgREST clients still can't join a transaction.
