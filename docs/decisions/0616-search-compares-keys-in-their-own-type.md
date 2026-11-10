# 0616: Search compares keys in their own type

- Status: accepted
- Date: 2026-11-10
- Amends: 0421

## Context

Search stored every record id as text, and the generator cast every key it
compared to text: the refresh join on a source view (`f.key::text = s.id::text`)
and every watch hop (`s.via::text = old.key::text`). The cast stops the planner
from using the primary key or the foreign key index. On a database with 65,020
orders, refreshing one order and finding a customer's orders both became
sequential scans of `orders`. A watch trigger with no `columns` also fired on
every update of the watched table, so a customer write scanned orders again.

## Decision

`search_refresh` joins a source view with `f.key = s.id` when the subject has an
`idType` (or the generator already knows both column types and they match), and
adds `f.key = (subject_id)::<idType>` so the planner can push the id into the
view. Watch hops and `via` compare the columns directly. The value passed to
`search_enqueue` is still text, because `search_documents.subject_id` is text.
When the subject has no `idType` and neither column's type is known, the
comparison stays text. When both types are known and they differ, the comparison
stays text and the generated file carries a comment. Doctor BS632 reports the
same pair from the live catalog.

A watch update trigger lists `key` and `watch.columns`, and its `when` clause
is `old.column is distinct from new.column` for each of them. Insert and delete
stay on their own trigger, because a `when` clause cannot read both `old` and
`new` on those events. Without `columns`, only a change to `key` re-indexes the
record. `columns` is the list of values the title or body reads from that table.
The drive subject lists `content` on `drive_node_texts`.

## Alternatives considered

- Keep the text casts and add expression indexes on `id::text`. Every foreign
  key would need one, and the planner would still not push the id into a view.
- Derive every column type from the block table definitions. The generator
  already knows `idType`, `uuid` columns and columns the app's files add. A
  column it does not know is assumed to share the subject's id type, and BS632
  checks that assumption against the database.

## Consequences

A search refresh and a watch lookup of a uuid key can use the key's index.
Changing a column a watch does not list no longer re-indexes the record. A
watch that used to re-index on any update, and that reads a value other than
`key`, has to name that column in `columns`. The drive subject does.
