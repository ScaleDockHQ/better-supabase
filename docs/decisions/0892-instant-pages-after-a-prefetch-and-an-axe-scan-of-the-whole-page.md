# 0892: Instant pages after a prefetch and an axe scan of the whole page

- Status: accepted
- Date: 2026-11-14

## Context

ADR 0891 left five pages on the allow list because the instant check timed out on them. The same
check also failed on other assistant pages that already passed, so the cause was not in the five
pages. In the trace the page stayed on the dashboard until the 30 second timeout. A push before
hydration does nothing, because `window.next.router` exists only after it, and a push to a route
the sidebar never prefetched (its group is collapsed) has no static shell to paint under the
instant lock. Waiting for network idle never settles on the dashboard, so it is no fix. ADR 0891 also scanned `main` only, because the shell's account,
organization and avatar controls failed two rules.

## Decision

- `pushRoute` waits for the router, prefetches the target and waits for the URL to commit (a
  client navigation fires no load event). The full spec then passes 156 of 156 without a retry.
  The five pages export `instant = true`, and the
  allow list keeps only the two init-fixture entries.
- The account and organization triggers lose their `aria-label`, whose text differed from the
  visible text. The visible name, the plan or role and a screen-reader suffix name the button, and
  the decorative mark and avatar are hidden from assistive technology. The avatar initials use
  `text-foreground` for contrast, and the search trigger's key hint is hidden from the name.
- `tests/accessibility.spec.ts` scans the whole page, not `main`.
- The `/members/invitations` page uses the read-only data grid (`RecordListGrid`) with its empty
  state and its Retry, as the ReUI rules ask for tables.

## Alternatives considered

Retries would hide the hang, and a longer test timeout would hide a hang that a user could see. Excluding the shell from the scan
would leave its controls unchecked.

## Consequences

The check now prefetches like a user who hovered the link. A route that is slow only when it was
never prefetched is not covered.
