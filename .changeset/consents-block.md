---
"better-supabase": minor
---

Add the `consents` block (`better-supabase/blocks/consents`): consent per record and purpose. An organization saves the purposes it asks consent for with `db.consents.savePurpose`, each with a lawful basis, a version, an optional signature requirement and a validity in months; the service role saves system purposes every organization uses. `record` stores a granted or refused decision for any subject with who made it (the person or a representative contact), its scope and a signature, form submission or attachment as evidence, and replaces the grant before it. `isActive(subject, purposeKey)` answers whether processing may go ahead on the current purpose version, `list` returns the latest decision per purpose or the full history, `withdraw` ends a grant, and the daily `consents.expire` timer marks grants past their valid-until date expired.

The permissions are `consents.read`, `consents.record` and `consents.manage`; members get none of them by default. A guest records and withdraws their own consent, and a guest whose person represents the record with `act` authority does so as a representative. The block writes `consent.granted`, `consent.refused`, `consent.withdrawn`, `consent.expired`, `consent_purpose.created` and `consent_purpose.updated` to the outbox, and ships the `consent-register` UI recipe.
