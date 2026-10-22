---
"better-supabase": minor
---

Add the `guests` block: clients and contractors invited by email who reach only the records you grant them, and a portal for the party they act for.

- `better-supabase add guests` installs guests and per-record grants. `createGuests` from `better-supabase/blocks/guests` invites by email (a one-time token whose email must match on accept), grants `read`, `comment` and `upload` on a record, revokes, and lists a record's guests or the caller's own access; `guestsSection` shows a record's guests on its page.
- Comments, attachments, invoices and bookings let guests in through the new `ctx.scope.guest` and `ctx.scope.guestParty` checks: a granted record, and the invoices addressed to the guest's party. Guests are never members, and without the block the policies don't change.
- An authorization provider can answer for guests through the optional `portalSubjects` and `portalParties` templates in `authorization.functions`; `apiVersion` stays 1.
