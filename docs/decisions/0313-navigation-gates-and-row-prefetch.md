# 0313: Prefetch record rows and gate their heavy body behind `navigation()`

- Status: accepted
- Date: 2026-11-07
- Amends: 0310

## Context

A record page reads `params`, so the shared App Shell cannot carry it. A default
`<Link>` loads only the shell, and `prefetch={true}` loads the whole page, heavy
sections included, for every row on screen. The example app had no gate, so the
customer rows either prefetched everything or nothing.

## Decision

- Rows of a record list link with `prefetch` (customers, forms, documents,
  courses, rules, workflow runs, project tasks, care clients). Long-tail links
  (breadcrumbs, drive items, chat history, calendar entries) keep the default.
- The heavy part of a record page awaits `navigation()` from `next/cache` in the
  async component, before its query call and outside every `'use cache'` scope,
  so a per-link prefetch carries the record's header and card and the page's
  side sections render on navigation behind their own boundary: the six
  customer detail sections (share links, attachments, relations, versions, SLA,
  timeline), the care plan editor and evaluations, consents and the access log.
  No wrapper query holds the gate.

## Consequences

A row prefetch costs the record's cached head read, not the whole page. The
`prefetch()` gate (render in a per-link prefetch but not in the shell) has no
caller yet, because every shell in the example is already static
(`ensureStatic = "shell"`). `bsb.cached(..., { stage })` would let the library
apply the same gate; see `docs/agents/nextjs.md`, "Library specs".
