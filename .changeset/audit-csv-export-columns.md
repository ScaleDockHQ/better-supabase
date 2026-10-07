---
"better-supabase": minor
---

`createAuditLog().export({ format: "csv" })` takes `columns`, `preamble` and `formatRow`. `columns` picks and orders the columns, with an optional header label each, and reads an adopted log's `metadataColumns` as `columns.<name>` and restricted details as `restricted.<field>` for callers who may reveal the entries. `preamble` writes lines before the header row, and `formatRow` changes each row before it is written. The new `reveal_audit_entries(entries)` function returns the restricted details of a page of entries and records one `audit.revealed` entry per tenant. Without these options the CSV is unchanged.
