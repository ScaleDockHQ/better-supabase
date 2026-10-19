# 0042: App table columns take a format, options and bounds; tables take composite keys and an id type

- Status: accepted
- Date: 2026-10-18

## Context

No-code database builders (Airtable, Baserow, NocoDB, Notion, Teable) offer
field types such as email, URL, rating, percent, currency, single and
multi-select and autonumber, and every one of them checks a select's
values. `appTables` (ADR 0040) only had plain Postgres types, so Create
could draw a `status` column but not limit it to its values, and an app had
to add every check, composite unique key and index by hand. A design must
still never carry free SQL: Create's codes are shareable links, and the CLI
writes them into the config without review.

## Decision

Each constraint is a structured key that the library renders, never an
expression:

- A column takes `format` (`email`, `url`, `phone`, `long_text`, `color`,
  `rating`, `percent`, `currency`), each valid only on the types it fits;
  `options` (1 to 100 values) on `text` or `text[]`; `min` and `max` (a
  value, or a length for `text`); `comment`; and `identity` on `integer` or
  `bigint`.
- A table takes `id: "uuid" | "bigint"`, `unique` and `indexes` (sets of
  column names) and `comment`. A reference to a table needs the type of its
  id.
- Checks are named `<table>_<column>_check` and written with
  `drop constraint if exists` then `add constraint`, so `sql sync` can
  change them; unique keys are `<table>_<columns>_key` and indexes
  `<table>_<columns>_idx`. The pgTAP file checks each one.
- Only `email`, `url`, `rating` and `percent` add a check; the other
  formats are hints for Create, forms and generators. Currency stays a
  `bigint` of minor units next to a `text` code (ADR 0037); Create splits a
  Currency column into `<name>_minor` and `<name>_currency`.

The design code keeps its `0` encoding character. Preset codes start with a
base62 version character, and version 1 is `1`, so a design code starting
with `1` would no longer be told apart from a preset code by its first
character. The design JSON gets a `version` key instead, written only when
the design uses a key from this release (`designFormat`), and a reader
rejects a `version` above `DESIGN_FORMAT` with a message to update.

## Alternatives considered

A free `check` expression per column covers every case, but puts SQL in a
link anyone can share, and the CLI would write it without review. Postgres
domains per format (`email_address`) would name the type in the schema, but
need their own migrations and change the column's type, which the typed
clients and `gen` read. Bumping the design code's first character was the
plan's first idea; it collides with preset codes as described above.

## Consequences

Codes from before this release decode unchanged, and a design that doesn't
use the new keys encodes to the same code. A release that reads only format
0 rejects a format 1 code instead of dropping its checks. The library's
email and URL checks are loose on purpose (an `@` and a dot, an
`http(s)://` prefix); an app that needs stricter rules validates in its
forms. Changing a table's id type in Create retypes the columns that
reference it; under the `migrations` workflow that change needs a migration
by hand, like any changed column.
