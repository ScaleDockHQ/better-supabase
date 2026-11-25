---
"better-supabase": minor
---

`organizations.inviteWithinSeats` and `saas.inviteWithinSeats` run as one database call. The new `invite_within_seats` function checks the invite permission, counts the members against the `seats` entitlement and invites in one transaction. The parts' TypeScript hooks (`organizations.members`, `entitlements.seatsLeft`, `organizations.invite`) no longer fire inside the composite; the composite's own hook does. A full plan answers `invalid_request` instead of `quota_exceeded`.
