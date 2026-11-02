# 0179: Adapters start from tested templates in `tests/adapter-templates`

- Status: accepted
- Date: 2026-11-01

## Context

The library bundles no provider for its ports: bank feeds (ADR 0153), route
optimizers (0158), shipping carriers (0082), payroll formats (0155), e-invoice
formats and channels (0159, 0172), chart formats (0159), clinical decision
support (0173) and prescription gateways (0178). The roadmap lists adapter
repositories that do not exist yet, and an author has only the port interface
and prose to start from.

## Decision

- `tests/adapter-templates` is a private workspace with one skeleton per port,
  written over an injected `fetch` and a shared `src/http.ts`, plus a test per
  skeleton against a fake `fetch`. The test runs the `better-supabase/testing`
  conformance block where one exists (`testShippingProvider`,
  `testClinicalDecisionSupport`, `testPrescriptionGateway`) and its own
  contract checks otherwise.
- The templates import only public subpaths, so the workspace also proves that
  each port's types are exported.
- `docs/extending/write-an-adapter` explains how to copy a template into a
  package and what every adapter keeps: `apiVersion`, error shape, idempotency,
  stable identifiers.
- No repository is created from this repo. A template becomes an adapter
  repository when someone owns a provider account to test against.

## Alternatives considered

- Conformance blocks for the six ports without one: worth doing next, but each
  adds a public export and a snapshot, so it is a separate change.
- A published `create-adapter` scaffold: rejected until two adapters exist to
  show what the scaffold should contain.

## Consequences

Each port has a copyable, tested starting point, and a change to a port that
breaks its template fails the workspace's typecheck in CI.
