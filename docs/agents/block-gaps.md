# Block gaps from the declarative base layer plan (Part 5)

Each line item of Part 5, checked against the code on `feat/bsb-declarative-base-layer`.
"Exists" means a module, client method or option already ships it. "Done" names the
commit that adds it. "Open" has a reason.

## Inventory

| Item                                        | State                                                                               |
| ------------------------------------------- | ----------------------------------------------------------------------------------- |
| `release_allocation`, `transfer_allocation` | Exists, with client methods and `allocation.transferred`                            |
| `api` reads                                 | Exists: `inventory_overview`, `stock_detail`, `stock_valuation`, `list_allocations` |
| unique `(id, tenant_id)`                    | Done (ADR 0267): locations, reservations, transfers, purchase orders                |
| `incoming`                                  | Exists: placing a purchase order adds it, receiving removes it                      |
| serial pick helper                          | Done (ADR 0267): `pick_serials`                                                     |
| reorder fields                              | Done (ADR 0267): `reorder_quantity`                                                 |
| purchase order document                     | Open: needs a purchase order source in the documents block                          |
| locale tax seed                             | Exists: `tax` seeds per locale (`nl`, `de`, `fr`)                                   |

## Parties and documents

| Item                                   | State                                                                                 |
| -------------------------------------- | ------------------------------------------------------------------------------------- |
| Person modes, company fields           | Open                                                                                  |
| Rate units                             | Open: rates are minor units per hour only                                             |
| Open-ended `subscription_periods`      | Open                                                                                  |
| Section lines                          | Exists on quotes; optional lines open                                                 |
| Discount cast                          | Open                                                                                  |
| Numbering scope                        | Exists: `scope` and `period` on sequences; `uniqueNumber` still an option on invoices |
| Orders from a quote, kitchen off       | Exists: orders confirm from an accepted quote, `kitchen` defaults to false            |
| Shipment direction                     | Lines carry `direction`; the shipment header has none (open)                          |
| Webhook endpoint CRUD                  | Exists: create, update, list, delete                                                  |
| Letterheads as a locale data migration | Open                                                                                  |

## Fields and work

| Item                                     | State                                                                           |
| ---------------------------------------- | ------------------------------------------------------------------------------- |
| Custom fields update, delete, seal       | Exists                                                                          |
| Tasks create fields, optional columns    | Open                                                                            |
| Time entries: `on` links, employee owner | Employee owner exists (`owner`); `on` links open                                |
| Leave ledger by employee                 | Exists (`owner: "employee"`)                                                    |
| Expenses employee owner                  | Exists (`owner: "employee"`)                                                    |
| Employees statuses from the app enum     | Open                                                                            |
| Hiring simplified                        | Exists: `stages`, `hiringManager`; further simplification open                  |
| Approvals request policy and floors      | Exists for floors (`options.policies`, tenant policies); extension columns open |

## Platform and runtime

| Item                                                              | State                                                           |
| ----------------------------------------------------------------- | --------------------------------------------------------------- |
| Comments avatar                                                   | Exists: `list_comments` returns the avatar with profiles        |
| Notifications `resolveAddress`                                    | Open                                                            |
| Realtime triggers as static app SQL                               | Open                                                            |
| Drive grants mode                                                 | Exists as role hooks (`DriveRoleHook`); a separate mode is open |
| Imports without events                                            | Exists: `events: "skip"`                                        |
| Outbox subject                                                    | Exists for app tables (`subjectType`, `subjectId`)              |
| Optional workflow tables                                          | Open                                                            |
| `approvalWaiter`, `resumeStreamResponse`, `problem429`            | Exists                                                          |
| `$decode` nested jsonb, fake client `PGRST116`, shim doctor rules | Exists (runtime-bugs, completed)                                |
