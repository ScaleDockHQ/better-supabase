# 1020: Split quotes and sequences into overview and detail, and add a companies route

- Status: accepted
- Date: 2026-11-14

## Context

Quotes and sequences were single pages that listed their records as cards, with
no URL for one record. Companies shared the contact route, so a company link
opened the person layout. The palette also had no way to open a create dialog
(EX-103).

## Decision

`/crm/quotes` and `/crm/sequences` are server-paged overviews on `BlockOverview`
with `/crm/quotes/[id]` and `/crm/sequences/[id]` as detail pages on
`RecordDetailFrame`. `/crm/companies` and `/crm/companies/[id]` render
`ContactOverview` and `ContactDetail` with `kind="company"`; a company id on the
contact route redirects to the companies route, so the generated search URL
`/crm/contacts/{id}` keeps working. The four create dialogs take `openFromUrl`
and open when the URL carries `?new=1`, and the command palette offers one create
action per entity the caller can write.

All five pages export `instant = true`, so `tests/routes.manifest.ts` and the
architecture allow list changed with them.

## Alternatives considered

Keeping the card lists was less work but gave a quote no link to share. Changing
the generated search URL for companies would have needed a config change and a
regeneration for one redirect.

## Consequences

Each CRM entity has a list and a record URL. The redirect is one extra hop for a
company opened from search. Revisit the redirect when the config can emit a URL
per subject kind.
