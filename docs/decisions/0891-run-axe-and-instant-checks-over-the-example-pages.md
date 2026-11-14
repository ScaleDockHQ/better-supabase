# 0891: Run axe and the instant check over the example pages

- Status: accepted
- Date: 2026-11-14

## Context

The audit left two checks open on the Next.js example. 86 routes exported `instant = false` or
nothing, so `scripts/app-architecture-allow.json` listed 82 findings (EX-024). No test ran an
accessibility engine over the generated pages (EX-1327). `@axe-core/playwright` 4.14.0 was released
on 2026-10-15, past `minimumReleaseAge`, so the supply-chain policy allows it.

## Decision

- 75 pages export `instant = true`, and their manifest entries say so. Each one passed
  `tests/instant-routes.spec.ts` in a production build with the testing API. The allow list drops to
  7 findings: five pages whose instant check loses its browser context (`/assistant/activity`,
  `/assistant/tasks`, `/settings/jobs`, `/shop/kitchen`, `/shop/kitchen/board`) and two in the init
  fixture. `instantInsights.validationLevel` stays at `warning` until the list is empty.
- `@axe-core/playwright` 4.14.0 is pinned in the catalog and is a devDependency of the example only.
  `tests/accessibility.spec.ts` runs one pass per route of `pages/coverage.ts` over `main`, with the
  WCAG 2.0 and 2.1 A and AA rules, and fails on serious and critical findings. The search trigger in
  the header lost its mismatched `aria-label` and its low-contrast key hint for it.
- `/members/invitations` gets the page its declaration named, which lists the open invitations
  through `invitationsPage`. Without it the coverage check failed on main.
- The generated list and export routes of a page with `tenantOption` answer 403 without a tenant and
  pass the option inside the `page` and `facets` options, because the reads typed it as required.

## Alternatives considered

Scanning the whole document fails on the shell's account, organization and avatar controls, which are
a design change of their own. Raising the rule set to moderate findings would gate on advice. Keeping
the five pages flaky-listed without a reason would hide the blocker.

## Consequences

Every new declared page gets an axe pass without a spec. The five instant pages need the lock
loss understood first. The shell controls are the remaining EX-1327 work.
