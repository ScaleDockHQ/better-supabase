import { describe, expect, it } from "vitest";

import { createInventory } from "../../../src/blocks/inventory/index.ts";
import { money } from "../../../src/commerce/index.ts";

function recorder(...results: unknown[]) {
  const calls: { fn: string; args: unknown }[] = [];

  return {
    calls,
    transport: {
      call(_schema: string, fn: string, args: unknown) {
        calls.push({ fn, args });

        return Promise.resolve(
          results.length > 1 ? results.shift() : results[0],
        );
      },
    },
  };
}

const REQUISITION = {
  id: "q1",
  organizationId: "org",
  locationId: "l1",
  supplierType: "company",
  supplierId: "s1",
  currency: "EUR",
  status: "pending",
  reason: "Low stock",
  requestedBy: "u1",
  decidedBy: null,
  decidedAt: null,
  approvalId: "a1",
  purchaseOrderId: null,
  createdAt: "2026-10-30T10:00:00Z",
  lines: [{ id: "ql1", variantId: "v1", quantity: "2.5", unitCost: "450" }],
};

describe("inventory purchase requisitions", () => {
  it("requests a purchase with costs in minor units", async () => {
    const { calls, transport } = recorder(REQUISITION);

    const requisition = await createInventory({ transport })
      .requestPurchase({
        organizationId: "org",
        input: {
          locationId: "l1",
          supplier: { type: "company", id: "s1" },
          reason: "Low stock",
          lines: [
            { variantId: "v1", quantity: 2.5, unitCost: money(450n, "EUR") },
          ],
        },
      })
      .orThrow();

    expect(calls[0]).toEqual({
      fn: "request_purchase",
      args: {
        tenant: "org",
        location: "l1",
        lines: [{ variantId: "v1", quantity: 2.5, unitCost: "450" }],
        supplier_type: "company",
        supplier_id: "s1",
        currency: "EUR",
        reason: "Low stock",
      },
    });
    expect(requisition).toMatchObject({
      id: "q1",
      status: "pending",
      supplier: { type: "company", id: "s1" },
      approvalId: "a1",
      lines: [{ id: "ql1", variantId: "v1", quantity: "2.5", unitCost: 450n }],
    });
    expect(requisition.purchaseOrderId).toBeUndefined();
    expect(requisition.createdAt.toString()).toBe("2026-10-30T10:00:00Z");
  });

  it("decides a requisition and orders approved ones", async () => {
    const { calls, transport } = recorder(
      { ...REQUISITION, status: "approved", approvalId: null },
      { id: "po1" },
      { ...REQUISITION, status: "ordered", purchaseOrderId: "po1" },
    );

    const inventory = createInventory({ transport });

    expect(
      (
        await inventory
          .decidePurchaseRequisition({ requisitionId: "q1", approve: true })
          .orThrow()
      ).status,
    ).toBe("approved");
    expect(
      await inventory
        .purchaseOrderFromRequisitions({
          requisitionIds: ["q1", "q2"],
          currency: "EUR",
        })
        .orThrow(),
    ).toEqual({ id: "po1" });
    expect(
      (await inventory.getPurchaseRequisition("q1").orThrow()).purchaseOrderId,
    ).toBe("po1");
    expect(calls.map((call) => call.fn)).toEqual([
      "decide_purchase_requisition",
      "purchase_order_from_requisitions",
      "get_purchase_requisition",
    ]);
    expect(calls[1]?.args).toEqual({
      requisitions: ["q1", "q2"],
      supplier_type: null,
      supplier_id: null,
      currency: "EUR",
    });
  });

  it("reads the receipt a purchase order delivery writes", async () => {
    const { transport } = recorder({
      status: "partially_received",
      backordered: 3,
      receiptId: "r1",
    });

    expect(
      await createInventory({ transport })
        .receivePurchaseOrder({
          purchaseOrderId: "po1",
          lines: [{ lineId: "pl1", quantity: 2 }],
        })
        .orThrow(),
    ).toEqual({
      status: "partially_received",
      backordered: 3,
      receiptId: "r1",
    });
  });
});
