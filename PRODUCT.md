# Product

## The promise

better-supabase gives a Supabase project a typed data layer, auth glue and a
CLI. `better-supabase gen` extends `supabase gen types` with relations, unique
keys, CHECK unions and typed jsonb, and every table gets a repository that
compiles to one PostgREST request, returns a `Result` instead of throwing, and
runs as the caller so RLS applies. The same client works in Next.js, Hono,
oRPC, Vite, Edge Functions and MCP servers.

## Users

- TypeScript developers who build apps, APIs, MCP servers and jobs on
  Supabase and want types that match the database.
- Teams that keep authorization in Postgres (RLS, custom access token hooks)
  and need the app side to follow it without calling the Auth server on every
  request.
- Coding agents working in those apps, through the consumer skills, the docs
  MCP server and `/llms.txt`.

## Scope

In scope: the typed client and repositories, codegen, auth helpers for the
supported frameworks, the SQL kit, storage and realtime helpers, testing
utilities, `doctor`, and plugins with a versioned interface.

Out of scope: hosting, a dashboard, a replacement for supabase-js or the
Supabase CLI, an ORM that bypasses PostgREST and RLS, and a permission model
(PermDock covers that, and better-supabase works next to it).

## Voice

Plain, complete sentences that say what a feature does and what the reader
runs next. Name the command, the option and the error. The writing rules in
`AGENTS.md` apply to the docs, the READMEs, the skills, the changesets and
the CLI.

## What we never claim

- That better-supabase is made or endorsed by Supabase.
- That it replaces RLS. It runs queries as the caller; the policies decide.
- Benchmark or size numbers without the measurement behind them
  (`tests/bundle/baseline.json`, the type-performance baseline).
- Support for a runtime, framework or TypeScript version that CI does not test.
- Production users or adoption we cannot name.
