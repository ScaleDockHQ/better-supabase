# 1028: Archive methods for invoices, risks, shipments and bookings (lane Y2, slice 1)

- Status: accepted
- Date: 2026-11-15

## Context

ADR 0839 pairs every `archive` with a `restore`, and ADR 0346 makes `archived_at`
the soft delete column. Invoices and risks map an `archived_at` column but had
no method that sets it, and an issued invoice cannot be deleted. Shipments and
bookings had neither a column nor a way to leave the lists.

## Decision

Each block gets an `archive` and a `restore` that record `archived` and
`restored` events once, and do nothing when the record is already in that state.

| Block       | Archives                                    | Permission            | Lists                                    |
| ----------- | ------------------------------------------- | --------------------- | ---------------------------------------- |
| `invoices`  | an invoice of any status                    | the delete permission | the app's own filter on `archivedAt`     |
| `risks`     | a risk of any status                        | `risks.manage`        | hidden already (`archivedAt is null`)    |
| `shipments` | a delivered, returned or cancelled shipment | `shipments.manage`    | hidden; the `archived` filter lists them |
| `bookings`  | a cancelled booking or one that has ended   | `bookings.manage`     | hidden; `includeArchived` lists them     |

Shipments and bookings gain an optional `archived_at` column. A record that is
still moving (a shipment in transit, an upcoming booking) is refused with
`SHIPMENT_ACTIVE` or `BOOKING_ACTIVE`, because an archive must not hide a record
that still holds stock or a slot. Invoices keep the opt-in `archivedAt` column,
so the functions exist for every install and fail with
`INVOICE_ARCHIVE_UNSUPPORTED` when the column is not mapped.

## Consequences

Each block adds two security-definer functions to the practices baseline.
`list_bookings` takes a fifth argument, `include_archived`, so the migration
drops and recreates it. The care-plan restore and the delete-only blocks
follow in the next slices.
