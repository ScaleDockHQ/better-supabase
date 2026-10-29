---
"better-supabase": minor
---

With `relations` installed, the `contacts` block contributes the relation kind `represents` (inverse `represented_by`) from a person to any record: a guardian, parent, mentor or emergency contact. Each link carries a `role` and an `authority` (`inform` or `act`) in its data, with optional `valid_from` and `valid_until` dates, and `link` refuses other data with `RELATION_DATA_INVALID`. `db.contacts.representativesOf(type, id)` lists a record's representatives, and `representedByMe(organizationId)` lists the records a guest's person represents.

The `guests` block takes `options.representation: { subjects: ["client"] }`. A guest who acts for a person then reaches the records of those types that the person actively represents: `read` with `authority: "inform"`, plus `comment` and `upload` with `authority: "act"`. The access follows the links live, so a link that ends closes the record without touching your grants.

Blocks that contribute a relation kind can now attach a check on the link's data; declaring a kind of the same name in `kinds` replaces the check too.
