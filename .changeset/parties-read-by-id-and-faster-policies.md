---
"better-supabase": minor
---

The contacts block reads one record by id: `getCompany(id)` and `getPerson(id)` return the active company or person, or `null` when it is archived, missing or hidden from the caller. Run `better-supabase upgrade` to add `get_company` and `get_person`.

The read policies of field history, observations, SLA clocks, pipeline history, consents, medication orders and funding awards check the record inline, as reactions and attachments do, so a member reads 12,000 rows of 60,000 records in tens of milliseconds, where `can_subject` per row took seconds. A record type whose team holds the read action still lets the team in. `upgrade` replaces the policies.

An import batch notes the records it changes for search in 256 settings instead of one, so a 30,000-record batch spends 130 ms there, where it spent 5,451 ms.
