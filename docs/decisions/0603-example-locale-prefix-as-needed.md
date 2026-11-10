# 0603: Route the example with localePrefix as-needed

- Status: accepted
- Date: 2026-11-10

## Context

With `localePrefix: "always"` every English URL carried `/en`. The plan asked for `as-needed`:
English URLs lose the prefix (`/projects`), Dutch keeps it (`/nl/projects`), and next-intl
redirects `/en/x` to `/x`. The proxy had three problems under it: `splitLocale` returned null for
an unprefixed path, so `protect` skipped the sign-in, waitlist and 403 checks for every English
page; a `protect` redirect won over the locale redirect `before` made for a visitor with
`NEXT_LOCALE=nl`; and redirect targets hardcoded the `/${locale}` prefix.

## Decision

- `splitLocale` returns the default locale for an unprefixed path.
- `localizedPath(locale, href)` in `i18n/routing.ts` (no React import) builds every redirect
  target and every URL a form hands to Auth. A rewrite (pricing, waitlist, 403) still names the
  internal `/[locale]/...` route, which always has the segment.
- The library skips `protect` when `before` returned a redirect, because the target passes
  through the proxy again (changeset, docs, a unit test).
- `AppConfig` types `Locale` as `"en" | "nl"`, and `isLocale` becomes next-intl's `hasLocale`.
- The Playwright specs use unprefixed paths, and `locale-routing.spec.ts` checks `/en/login` to
  `/login`, a signed-out `/projects` to `/login`, `/nl/projects` to `/nl/login`, and the
  `NEXT_LOCALE` cookie to `/nl/login`.

## Consequences

The build still prerenders the shells as partial prerenders, so no route became dynamic; all 26
specs but one pass (`bench-scopes` fails only in the full run and passes alone, twice). Not
checked: `getExtracted` inside `"use cache"` with root params, which the build accepted.
