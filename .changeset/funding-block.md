---
"better-supabase": minor
---

New `funding` block (`better-supabase/blocks/funding`): funding products with a rate per unit, awards that grant a record units per period from a funder, deliveries registered against them, and claims a funder answers line by line.

- `saveProduct` keeps the products a funder pays for, each with a unit and a rate as `Money`. `createAward`, `updateAward` and `endAward` record the units a funder (a contacts party with the `funder` role) awards a record in `config.subjects`, per week, per month or in total; `usage` returns the units used against the units awarded for each period.
- `registerDelivery` records care or service delivered on an active award. `registerFromTime` (service role) registers the approved time entries of the period on the record's one active award and returns the entries it couldn't match. `approveDeliveries` approves registered deliveries or rejects them.
- `buildClaim` collects a funder's approved deliveries of a period into a draft claim, numbered through numbering when it is installed. `send` renders it with a `FundingClaimFormat` and sends it through a `FundingClaimChannel` (both `apiVersion: 1`; no format or channel is bundled); `markSent` records a claim sent another way. `poll` and `recordResponse` record the funder's answer per line, and a rejected line puts its deliveries back to `approved` for a later claim. `invoiceClaim` creates an invoice to the funder when invoices is installed.
- Usage above an award records the `funding_award.exceeded` event and notifies the members who manage funding.
- `better-supabase/testing` gains `testFundingClaimFormat` and `testFundingClaimChannel` to check a format or channel.
- The permission keys are `funding.read`, `funding.write`, `funding.register`, `funding.approve`, `funding.claim` and `funding.manage`; members get `read` and `register`.

Add `funding: {}` to `blocks`, run `better-supabase add funding` and generate a migration.
