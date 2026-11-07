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
| purchase order document                     | Done (ADR 0268): the `purchase_order` document type                                 |
| locale tax seed                             | Exists: `tax` seeds per locale (`nl`, `de`, `fr`)                                   |

## Parties and documents

| Item                                   | State                                                                      |
| -------------------------------------- | -------------------------------------------------------------------------- |
| Person modes, company fields           | Done (ADR 0268): `people.mode`, `legal_name`, `registration_id`, `phone`   |
| Rate units                             | Done (ADR 0268): `unit` on document lines; time rates stay per hour        |
| Open-ended `subscription_periods`      | Done (ADR 0268): `periods` null                                            |
| Section and optional lines             | Exists on quotes (`section`, `optional`, `selected`)                       |
| Discount cast                          | Done (ADR 0268): `discount_kind`, typed over an app enum                   |
| Numbering scope                        | Done (ADR 0268): `uniqueNumber` removed, invoices unique by identifier     |
| Orders from a quote, kitchen off       | Exists: orders confirm from an accepted quote, `kitchen` defaults to false |
| Shipment direction                     | Done (ADR 0268): `shipments.direction`, `set_shipment_direction`           |
| Webhook endpoint CRUD                  | Exists: create, update, list, delete                                       |
| Letterheads as a locale data migration | Done (ADR 0268): the `letterhead` seed of document-templates               |

## Fields and work

| Item                                     | State                                                                   |
| ---------------------------------------- | ----------------------------------------------------------------------- |
| Custom fields update, delete, seal       | Exists                                                                  |
| Tasks create fields, optional columns    | Done (ADR 0269): `fields` on create existed; `locked` is optional       |
| Time entries: `on` links, employee owner | Done (ADR 0269): `options.on`; the employee owner exists (`owner`)      |
| Leave ledger by employee                 | Exists (`owner: "employee"`)                                            |
| Expenses employee owner                  | Exists (`owner: "employee"`)                                            |
| Employees statuses from the app enum     | Exists: `typed` status with value maps (`employees-shapes.test.ts`)     |
| Hiring simplified                        | Exists: `stages`, `hiringManager`; no further change named (ADR 0269)   |
| Approvals request policy and floors      | Exists: floors, tenant policies, extra columns on requests and policies |

## Platform and runtime

| Item                                                              | State                                                                       |
| ----------------------------------------------------------------- | --------------------------------------------------------------------------- |
| Comments avatar                                                   | Exists: `list_comments` returns the avatar with profiles                    |
| Notifications `resolveAddress`                                    | Done (ADR 0270): `options.resolveAddress`                                   |
| Realtime triggers as static app SQL                               | Done (ADR 0270): static `create trigger` statements                         |
| Drive grants mode                                                 | Role hooks exist (`DriveRoleHook`); a separate mode is not built (ADR 0270) |
| Imports without events                                            | Exists: `events: "skip"`                                                    |
| Outbox subject                                                    | Exists for app tables (`subjectType`, `subjectId`)                          |
| Optional workflow tables                                          | Done (ADR 0270): `workflow_opt_outs` is optional                            |
| `approvalWaiter`, `resumeStreamResponse`, `problem429`            | Exists                                                                      |
| `$decode` nested jsonb, fake client `PGRST116`, shim doctor rules | Exists (runtime-bugs, completed)                                            |
