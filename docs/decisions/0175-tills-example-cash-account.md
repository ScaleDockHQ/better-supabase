# 0175: The tills example creates each till with a cash account

- Status: accepted
- Date: 2026-11-01

## Context

ADR 0171 made `accountId` optional on a till and booked a count's variance only
when the till has one. The example app's Add a till button left it empty, so the
example never showed a count booking anything.

## Decision

The example's `createTill` action ensures the organization has an accounting chart
(`setup` when `settings` is empty), then plans the cash account with the pure
function `planCashAccount`: an active euro asset account with "cash" in its name
that no till uses is mapped, otherwise a new asset account is saved on the next
free code from 1000. The action then creates the till with that `accountId`.

The block and the database do not change. The planner lives beside the action and
has a unit test, because the action itself runs only under the app.

## Consequences

- A new till's count books its variance in the example without setup by hand.
- Two tills never share a cash account through the button.
- An app with its own chart rules replaces `planCashAccount` and keeps the call.
