---
"better-supabase": minor
---

New `manufacturing` block (`better-supabase/blocks/manufacturing`): bills of materials, production orders over inventory, lot genealogy and material requirements.

- `saveBom` saves a draft version of a variant's bill of materials with its components and routing, and `activateBom` makes it the active version and archives the previous one; a cycle fails with `BOM_CYCLE`. `explodeBom` and `whereUsed` walk every level.
- `saveWorkCenter` keeps the work centers, each with a cost rate per hour and, with the assets block, its machine.
- `createOrder` creates a production order numbered `MO-2026-0001`. `release` allocates the components and fails with `PRODUCTION_ORDER_SHORTAGE` unless `allowShortage`. `startOperation`, `finishOperation` and `recordConsumption` run it, and `complete` backflushes the rest and receives the output at the material cost plus labor. `cancel` returns what was consumed.
- `lotGenealogy` lists the lots a lot was made from or went into, and `lotRecall` the lots, stock, documents and orders a recall reaches.
- `requirements` suggests what to produce or buy, and `createFromRequirements` turns the suggestions into draft production orders and purchase orders.
- Inventory gains the movement reasons `consumption` and `production`, and `take_allocation`, which `fulfill_allocation` now calls. Accounting gains the `work_in_progress` role (account 1350 in the generic chart): stock movements of those reasons book to it, and a completed order's labor books as the `production_order` source.
- The permission keys are `manufacturing.read`, `manufacturing.write`, `manufacturing.produce` and `manufacturing.manage`; members get `read` and `produce`.

Add `manufacturing: {}` to `blocks`, run `better-supabase add manufacturing` and generate a migration. Projects with inventory or accounting get the new reasons and role on their next `upgrade`. An organization that ran accounting `setup` before maps the role with `setAccountRole(organizationId, "work_in_progress", accountId)`; until then those lines book to `suspense`.
