# 0959: Name input fields and subjects in the example

- Status: accepted
- Date: 2026-11-14

## Context

Lane C added `fields` to `invalid_input` (ADR 0709) and lane N added
`subjects.label` and the party core (ADR 0829). The example still checked the
asset kind with an HTML pattern, asked for the warranty decision with a
`required` attribute, printed review and segment subjects as ids and showed no
deals in the inbox. `/qualifications` carried a bundle outlier (EX-1505).

## Decision

Forms place a rejection next to its input. `src/lib/input-field-messages.ts`
reads the `fields` of an `invalid_input` error and the issues of a
`validation` error. The warranty decide action returns `invalid_input` for a
missing decision, and the asset action maps the `bsb_assets_kind_check`
constraint to a `kind` field.

Names come from `subjects.label`: the moderation queue and detail of reviews,
segment members and top scores. The inbox context pane lists the open deals
that name the contact (an inbox contact is a CRM person) and names each deal's
company through `createPartyResolver`. The pane loads them from
`/api/inbox/contact-deals` after the thread paints, because importing the
deals block into the inbox page grew its server chunks by 388 KB gzip.

Search columns for contacts come from `blocks.contacts.names.<entity>.search`
(EX-101). The CLI config schema did not accept `search` under `names`, so this
lane adds it (changeset).

`/qualifications` shares its list kit with every list page; its first load is
within 7 KB gzip of risks, maintenance and assets, so no baseline moves for it.
The first-load baseline rises by under 3 KB gzip on the inbox thread and by a
few hundred raw bytes on the assets, warranty detail and work grid pages, set to
the measured values like ADR 0790.

## Alternatives considered

Loading the deals in the inbox server component was simpler but doubled the
server chunks of both inbox pages. Lazy-loading the list kit on
`/qualifications` would have made every list page paint later for a gap that no
longer exists.

## Consequences

An action that wants a field message returns `invalidInput` with the input's
path. The library types `search.body` with database column names but validates
logical names, so only single-word columns work for now; revisit when the
type follows the validation.
