---
"better-supabase": minor
---

`list_rfqs`, `list_samples`, `list_till_sessions` and `list_calibrations` page through the keyset list template of ADR 0637, with a list index that ends in the id. `rfqs.rfqPage`, `lims.samplePage`, `tills.sessionPage` and `maintenance.calibrationPage` return `{ items, hasMore, nextCursor }`, and `total` when asked. Doctor BS633 reports an app row trigger whose function never calls `better_supabase.importing()`.

Migration guide for the moved lists:

| Before                                        | After                                                                              |
| --------------------------------------------- | ---------------------------------------------------------------------------------- |
| `listSamples({ offset: 100 })`                | Still works. Keep it where you show page numbers.                                  |
| `listSamples({ offset, after })`              | Refused with an invalid error. Pass one of them.                                   |
| Deep paging with `offset`                     | `samplePage({ after: page.nextCursor })`, which reads from the index at any depth. |
| Rows with equal `performed_at` or `opened_at` | Come back in id order, the same order as before.                                   |

The same applies to `listRfqs` with `rfqPage`, `listSessions` with `sessionPage` and `listCalibrations` with `calibrationPage`. Run `supabase db diff` to pick up the new list indexes. The remaining offset lists keep their shape.
