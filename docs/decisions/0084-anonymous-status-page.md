# 0084: The public status page is one security definer function anon may call

- Status: accepted
- Date: 2026-10-22

## Context

The `incidents` block keeps incidents, their timeline updates, the components
they affect and their postmortems per organization. A status page has to show
part of that to anyone, signed in or not: the components a customer depends
on, their current status, their uptime, and the updates the team chose to
publish. The rest stays private: internal components, private incidents,
private updates, the incident description, the commander, postmortem root
causes and action items, and every other organization's data.

Every other block grants nothing to `anon`, and each table has RLS that reads
the active tenant from the JWT. An anonymous reader has no tenant, so the
usual policies can't express "this one published page".

## Decision

`anon` gets no table privileges on any incidents table. It may execute one
function, `public_status_page(slug, days)` (and its `api` wrapper), which is
`security definer` with `search_path = ''`. The function:

- returns null unless a page with that slug exists and is `published`;
- reads only the organization that owns the page, found by the unique slug;
- builds its result field by field: the page title and description, the
  components marked `public` with their status and a daily uptime series from
  `status_component_history`, and the `public` incidents (open, or resolved
  inside the window) with only their title, severity, status, start and end,
  the public components they affect, their `public` updates and the summary
  of a published postmortem;
- clamps `days` to 1 through 90, so a caller can't make it scan more history.

Ids of tenants, members and private rows never appear in the result. Slugs are
unique across organizations (`STATUS_PAGE_SLUG_TAKEN`), so one slug never
names two pages.

`supabase/tests/database/incidents.test.sql` proves the surface: anon has no
privileges on the tables, the two `public_status_page` functions are the only
incidents functions anon can execute, a private incident, a private update and
a private component never appear in the page, and an unpublished page is null.

## Alternatives considered

- A view granted to `anon`. RLS on the underlying tables would need an anon
  policy per table, and a view exposes every column it selects to filters and
  joins. A missed `where public` in one policy would leak a whole table.
- A separate public schema filled by triggers. It duplicates the data and has
  to stay in step with every update, impact and postmortem change.
- Serving the page only from the app's server with the service role. That
  works, but every app would repeat the filtering, and a static or edge status
  page couldn't read it with the publishable key.

## Consequences

- The public surface is one function whose output fields are listed in
  `incidents-status-page.ts`; reviewing what anon can see means reading that
  function.
- A new public field needs a change to the function and to the pgTAP test.
- An app calls it with the publishable key from any runtime, signed in or
  not; the example's `(public)/status/[slug]` route does.
- Rate limiting anonymous reads is up to the app or the edge; the function
  doesn't count calls.
