import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createContacts } from "../../src/blocks/contacts/index.ts";
import { createInventory } from "../../src/blocks/inventory/index.ts";
import { createInvoices } from "../../src/blocks/invoices/index.ts";
import { money } from "../../src/commerce/money.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();
const eur = (amount: bigint) => money(amount, "EUR");

const MODULES = [
  "organizations",
  "outbox",
  "catalog",
  "contacts",
  "inventory",
  "invoices",
];

const layout: BlockSqlLayout = {
  subjects: withBlockSubjects({}, ["contacts"], {}),
};

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("purchasing", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("requests, orders, receives and matches a bill against the receipt", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("buyer");
      const member = await s.user("clerk");
      await s.install(MODULES, layout);
      const org = await s.organization(owner, { member });
      const transport = sqlTransport(s.sql);
      const parties = createContacts({ transport });
      const inventory = createInventory({ transport });
      const invoices = createInvoices({ transport });

      await s.as(owner);

      const product = await s.value<{ id: string }>(
        "better_supabase.save_product($1, null, 'Bolts', null, null, 'physical')",
        [org],
      );

      const variant = await s.value<{ id: string }>(
        "better_supabase.save_variant($1, null, 'BOLT', '{}'::uuid[], null, null, null, true, false)",
        [product.id],
      );

      const dock = await inventory
        .saveLocation({
          organizationId: org,
          input: { code: "DOCK", name: "Dock" },
        })
        .orThrow();

      const supplier = await parties
        .saveCompany({ organizationId: org, input: { name: "Bolt supplier" } })
        .orThrow();

      await parties
        .setSupplierStatus({ partyId: supplier.id, status: "blocked" })
        .orThrow();
      expect(
        await inventory
          .savePurchaseOrder({
            organizationId: org,
            input: {
              locationId: dock.id,
              supplier: { type: "company", id: supplier.id },
              currency: "EUR",
              lines: [
                { variantId: variant.id, quantity: 5, unitCost: eur(200n) },
              ],
            },
          })
          .then(hint),
      ).toBe("PURCHASE_ORDER_SUPPLIER_BLOCKED");
      await parties
        .setSupplierStatus({ partyId: supplier.id, status: "approved" })
        .orThrow();

      const requisition = await inventory
        .requestPurchase({
          organizationId: org,
          input: {
            locationId: dock.id,
            supplier: { type: "company", id: supplier.id },
            currency: "EUR",
            lines: [
              { variantId: variant.id, quantity: 5, unitCost: eur(200n) },
            ],
            reason: "Below the reorder point",
          },
        })
        .orThrow();

      expect(requisition).toMatchObject({ status: "pending", lines: [{}] });

      const approved = await inventory
        .decidePurchaseRequisition({
          requisitionId: requisition.id,
          approve: true,
        })
        .orThrow();

      expect(approved.status).toBe("approved");

      const order = await inventory
        .purchaseOrderFromRequisitions({ requisitionIds: [requisition.id] })
        .orThrow();

      expect(
        (await inventory.getPurchaseRequisition(requisition.id).orThrow())
          .purchaseOrderId,
      ).toBe(order.id);

      await inventory.placePurchaseOrder(order.id).orThrow();

      const lines = await s.rows<{ id: string }>(
        "select id from better_supabase.purchase_order_lines where purchase_order_id = $1",
        [order.id],
      );

      const receipt = await inventory
        .receivePurchaseOrder({
          purchaseOrderId: order.id,
          lines: lines.map((line) => ({ lineId: line.id, quantity: 3 })),
        })
        .orThrow();

      expect(receipt).toMatchObject({ status: "partially_received" });
      expect(receipt.receiptId).toBeTypeOf("string");

      const billInput = {
        title: "Bolts",
        direction: "purchase",
        company: { type: "company", id: supplier.id },
        supplierReference: "S-100",
        purchaseOrderId: order.id,
      } as const;

      const billLines = [
        {
          product: { type: "product_variant", id: variant.id },
          description: "Bolts",
          quantity: 5,
          unitAmount: eur(200n),
        },
      ];

      await s.as(member);
      expect(
        await invoices
          .create({ organizationId: org, input: billInput, lines: billLines })
          .then(hint),
      ).toBe("INVOICE_FORBIDDEN");

      await s.as(owner);

      const draft = await invoices
        .create({ organizationId: org, input: billInput, lines: billLines })
        .orThrow();

      expect(draft).toMatchObject({
        direction: "purchase",
        supplierReference: "S-100",
        purchaseOrderId: order.id,
      });

      const bill = await invoices.issue({ invoiceId: draft.id }).orThrow();

      expect(bill.identifier).toBe("BILL-1");

      const match = await invoices.match(bill.id).orThrow();

      expect(match.status).toBe("quantity_variance");

      await s.service();
      expect(
        (
          await s.rows<{ type: string }>(
            "select type from better_supabase.outbox_events where organization_id = $1 and type in ('purchase_requisition.created', 'purchase_requisition.approved', 'inventory_receipt.created', 'invoice.match_checked') order by position",
            [org],
          )
        ).map((row) => row.type),
      ).toEqual([
        "purchase_requisition.created",
        "purchase_requisition.approved",
        "inventory_receipt.created",
        "invoice.match_checked",
      ]);
    } finally {
      await s.close();
    }
  });
});
