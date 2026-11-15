---
"better-supabase": minor
---

`invoices`, `risks`, `shipments` and `bookings` get an archive and a restore,
so a record that cannot be deleted can leave the lists and come back.

| Block       | New methods                                | New events                               | Rule                                                                    |
| ----------- | ------------------------------------------ | ---------------------------------------- | ----------------------------------------------------------------------- |
| `invoices`  | `archive(invoiceId)`, `restore(invoiceId)` | `invoice.archived`, `invoice.restored`   | any status; needs the opt-in `archivedAt` column                        |
| `risks`     | `archive(riskId)`, `restore(riskId)`       | `risk.archived`, `risk.restored`         | any status; needs `risks.manage`                                        |
| `shipments` | `archive(id)`, `restore(id)`               | `shipment.archived`, `shipment.restored` | delivered, returned or cancelled; the `archived` list filter shows them |
| `bookings`  | `archive(bookingId)`, `restore(bookingId)` | `booking.archived`, `booking.restored`   | cancelled or ended; `list` takes `includeArchived`                      |

`shipments` and `bookings` get an `archived_at` column, `Shipment` and `Booking`
carry `archivedAt`, and `list_bookings` takes a fifth argument,
`include_archived`. An app table made before the column maps `archivedAt: null`
in `columns.shipments` or `columns.bookings` to leave the pair out. Run
`better-supabase upgrade` and apply the migration.
