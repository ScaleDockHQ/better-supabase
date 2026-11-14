# 1021: Add schedule views, owner assignment and the buyer thread to the deal desk

- Status: accepted
- Date: 2026-11-14

## Context

The deals page showed a table and a board. A sales lead also needs to see
closing dates on a calendar, a timeline of open deals by month, a way to move
several deals to one owner, and the buyer's conversation without leaving the
deal (EX-601).

## Decision

`/crm/deals` gains `?tab=calendar` (a month grid with `?month=YYYY-MM`) and
`?tab=timeline` (open deals grouped by close month, each amount as a bar), both
server components over `loadDeals`. The table tab shows an Assign owner dialog
for callers with `deals.write`; it posts up to 100 deal ids and one owner to
`assignDealOwners`, which sends one `deals.update` call with `ownerId` changes
and reports how many deals were assigned and refused.

The deal page gets a Conversation tab for callers with `inbox.read`. It renders
the inbox `ConversationPanel`, so a reply or an assignment on the deal desk lands
in the unibox queue. The deals block lists deals by a person and has no read for a
deal's contacts, so `loadDealConversations` reads the people on the deal's
relations binding in one call and keeps the newest 50 conversations whose
contact is one of them. A per-contact `deals.list` loop was the first version;
doctor rule BS634 reported it as an N+1.

## Alternatives considered

Adding row selection to the shared list grid would touch every overview. A
`deals.contacts` read in the block is the better long-term fix, but it is a
library change outside this lane.

## Consequences

The conversation lookup makes two reads, the conversations and the relations,
cached per organization and tagged for the inbox, CRM and sales. A buyer shows
once someone links their person record on the Related tab, and a buyer whose
conversations are older than the newest 50 does not show. Revisit when the deals
block reads a deal's contacts.
