import * as v from "valibot";
import { describe, expect, it } from "vitest";

import {
  bomInputSchema,
  createManufacturing,
  manufacturingBlock,
  productionOrderInputSchema,
  workCenterInputSchema,
} from "../../../src/blocks/manufacturing/index.ts";
import { money } from "../../../src/commerce/money.ts";
import { temporal } from "../../../src/core/temporal-required.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-30T10:00:00Z";

const BOM = {
  id: "b1",
  organizationId: "org-1",
  variantId: "bread",
  version: 2,
  status: "active",
  quantity: "1",
  note: null,
  activatedAt: AT,
  createdAt: AT,
  updatedAt: AT,
  components: [
    {
      id: "c1",
      variantId: "flour",
      quantity: "0.5",
      scrapBps: 200,
      operationId: "o1",
      position: 1,
    },
  ],
  operations: [
    {
      id: "o1",
      sequence: 10,
      workCenterId: "w1",
      title: "Bake",
      setupMinutes: "5",
      runMinutesPerUnit: "6",
      instructionsNodeId: null,
      inspectionTemplate: "inspection",
    },
  ],
};

const WORK_CENTER = {
  id: "w1",
  organizationId: "org-1",
  name: "Oven",
  assetId: null,
  hoursPerDay: "8",
  costRate: "6000",
  currency: "EUR",
  archivedAt: null,
  createdAt: AT,
  updatedAt: AT,
};

const ORDER = {
  id: "mo1",
  organizationId: "org-1",
  number: "MO-2026-0001",
  variantId: "bread",
  bomId: "b1",
  quantity: "4",
  locationId: "l1",
  dueOn: "2026-11-02",
  status: "done",
  producedQuantity: "4.000000",
  scrapQuantity: "0.000000",
  outputLotId: "lot-bread",
  materialCost: "800",
  laborCost: "2400",
  currency: "EUR",
  note: null,
  releasedAt: AT,
  startedAt: AT,
  completedAt: AT,
  canceledAt: null,
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
  fields: { line: "north" },
  operations: [
    {
      id: "op1",
      orderId: "mo1",
      operationId: "o1",
      sequence: 10,
      workCenterId: "w1",
      title: "Bake",
      plannedMinutes: "24.00",
      status: "done",
      startedAt: AT,
      finishedAt: AT,
      operatorId: "u2",
      minutes: "24.00",
      inspectionId: null,
    },
  ],
  components: [
    {
      componentId: "c1",
      variantId: "flour",
      quantity: "2.040",
      allocated: "0",
      backordered: "0",
      consumed: "2.040000",
    },
  ],
  consumptions: [
    {
      id: "pc1",
      variantId: "flour",
      lotId: "lot-flour",
      serial: null,
      quantity: "2.040000",
      cost: "408",
      currency: "EUR",
      movementId: "m1",
      createdAt: AT,
    },
  ],
};

const Fields = v.object({ line: v.picklist(["north", "south"]) });

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createManufacturing", () => {
  it("saves, activates and reads bills of materials", async () => {
    const t = fieldsTransport({
      save_bom: () => ({ ...BOM, status: "draft", activatedAt: null }),
      activate_bom: () => BOM,
      list_boms: () => [BOM],
      explode_bom: () => ({
        variantId: "bread",
        quantity: "4",
        lines: [
          {
            level: 1,
            variantId: "flour",
            parentVariantId: "bread",
            bomId: "b1",
            quantity: "2.040",
            made: false,
          },
        ],
        materials: [{ variantId: "flour", quantity: "2.040" }],
      }),
      bom_where_used: () => [
        {
          level: 1,
          bomId: "b1",
          variantId: "bread",
          version: 2,
          status: "active",
          quantity: "0.5",
        },
      ],
    });

    const manufacturing = createManufacturing({
      transport: t,
      tenant: "org-1",
    });

    const draft = await manufacturing
      .saveBom({
        variantId: "bread",
        input: {
          components: [
            { variantId: "flour", quantity: 0.5, scrapBps: 200, operation: 10 },
          ],
          operations: [
            {
              sequence: 10,
              workCenterId: "w1",
              title: "Bake",
              runMinutesPerUnit: 6,
            },
          ],
        },
      })
      .orThrow();

    const active = await manufacturing.activateBom("b1").orThrow();
    const versions = await manufacturing.listBoms("bread").orThrow();

    const explosion = await manufacturing
      .explodeBom({ variantId: "bread", quantity: 4 })
      .orThrow();

    const uses = await manufacturing.whereUsed("flour").orThrow();

    expect(draft.status).toBe("draft");
    expect(draft.activatedAt).toBeUndefined();
    expect(draft.components[0]).toEqual({
      id: "c1",
      variantId: "flour",
      quantity: 0.5,
      scrapBps: 200,
      position: 1,
      operationId: "o1",
    });
    expect(draft.operations[0]).toMatchObject({
      setupMinutes: 5,
      runMinutesPerUnit: 6,
      inspectionTemplate: "inspection",
    });
    expect(active.activatedAt?.toString()).toBe(AT);
    expect(versions[0]?.version).toBe(2);
    expect(explosion.materials).toEqual([
      { variantId: "flour", quantity: 2.04 },
    ]);
    expect(explosion.lines[0]?.made).toBe(false);
    expect(uses[0]).toMatchObject({ variantId: "bread", quantity: 0.5 });
    expect(t.calls[0]).toEqual([
      "save_bom",
      {
        tenant: "org-1",
        variant: "bread",
        input: {
          quantity: 1,
          note: null,
          components: [
            { variantId: "flour", quantity: 0.5, scrapBps: 200, operation: 10 },
          ],
          operations: [
            {
              sequence: 10,
              workCenterId: "w1",
              title: "Bake",
              setupMinutes: 0,
              runMinutesPerUnit: 6,
              instructionsNodeId: null,
              inspectionTemplate: null,
            },
          ],
        },
        bom_id: null,
      },
    ]);
    expect(t.calls.slice(1).map(([fn, args]) => [fn, args])).toEqual([
      ["activate_bom", { bom_id: "b1" }],
      ["list_boms", { tenant: "org-1", variant: "bread" }],
      ["explode_bom", { variant_id: "bread", quantity: 4 }],
      ["bom_where_used", { variant_id: "flour" }],
    ]);
  });

  it("saves work centers with a cost rate in money", async () => {
    const t = fieldsTransport({
      save_work_center: () => WORK_CENTER,
      list_work_centers: () => [{ ...WORK_CENTER, currency: null }],
    });

    const manufacturing = createManufacturing({
      transport: t,
      tenant: "org-1",
    });

    const saved = await manufacturing
      .saveWorkCenter({ input: { name: "Oven", costRate: money(6000, "EUR") } })
      .orThrow();

    const listed = await manufacturing.workCenters().orThrow();

    expect(saved.costRate).toEqual(money(6000, "EUR"));
    expect(saved.hoursPerDay).toBe(8);
    expect(listed[0]?.costRate).toBeUndefined();
    expect(t.calls[0]).toEqual([
      "save_work_center",
      {
        tenant: "org-1",
        input: { name: "Oven", costRate: "6000", currency: "EUR" },
        work_center_id: null,
      },
    ]);
  });

  it("runs a production order and checks its extra fields", async () => {
    const t = fieldsTransport({
      create_production_order: () => ({ ...ORDER, status: "draft" }),
      release_production_order: () => ({ ...ORDER, status: "released" }),
      start_production_operation: () => ({ ...ORDER, status: "in_progress" }),
      finish_production_operation: () => ORDER,
      record_production_consumption: () => ORDER,
      complete_production_order: () => ORDER,
      cancel_production_order: () => ({ ...ORDER, status: "canceled" }),
      list_production_orders: () => [ORDER],
    });

    const manufacturing = createManufacturing({
      transport: t,
      tenant: "org-1",
      fields: Fields,
    });

    const created = await manufacturing
      .createOrder({
        variantId: "bread",
        quantity: 4,
        dueOn: temporal().PlainDate.from("2026-11-02"),
        fields: { line: "north" },
      })
      .orThrow();

    await manufacturing
      .release({ orderId: "mo1", allowShortage: true })
      .orThrow();
    await manufacturing.startOperation("op1").orThrow();
    await manufacturing
      .finishOperation({ operationId: "op1", minutes: 24 })
      .orThrow();
    await manufacturing
      .recordConsumption({
        orderId: "mo1",
        variantId: "flour",
        quantity: 2.04,
        detail: { lotId: "lot-flour" },
      })
      .orThrow();

    const done = await manufacturing
      .complete({ orderId: "mo1", produced: 4, scrap: 1, lot: { code: "B-1" } })
      .orThrow();

    const canceled = await manufacturing
      .cancel({ orderId: "mo2", reason: "Dropped" })
      .orThrow();

    const listed = await manufacturing
      .listOrders({ status: "done", limit: 10 })
      .orThrow();

    expect(created.fields).toEqual({ line: "north" });
    expect(created.dueOn?.toString()).toBe("2026-11-02");
    expect(done).toMatchObject({
      producedQuantity: 4,
      outputLotId: "lot-bread",
      materialCost: money(800, "EUR"),
      laborCost: money(2400, "EUR"),
    });
    expect(done.operations[0]).toMatchObject({ minutes: 24, operatorId: "u2" });
    expect(done.components[0]?.consumed).toBe(2.04);
    expect(done.consumptions[0]).toMatchObject({
      lotId: "lot-flour",
      cost: money(408, "EUR"),
    });
    expect(done.consumptions[0]?.serial).toBeUndefined();
    expect(canceled.status).toBe("canceled");
    expect(listed).toHaveLength(1);
    expect(t.calls.map(([fn, args]) => [fn, args])).toEqual([
      [
        "create_production_order",
        {
          tenant: "org-1",
          input: {
            variantId: "bread",
            quantity: 4,
            dueOn: "2026-11-02",
            fields: { line: "north" },
          },
        },
      ],
      ["release_production_order", { order_id: "mo1", allow_shortage: true }],
      ["start_production_operation", { operation_id: "op1" }],
      ["finish_production_operation", { operation_id: "op1", minutes: 24 }],
      [
        "record_production_consumption",
        {
          order_id: "mo1",
          variant: "flour",
          quantity: 2.04,
          detail: { lotId: "lot-flour" },
        },
      ],
      [
        "complete_production_order",
        { order_id: "mo1", produced: 4, scrap: 1, lot: { code: "B-1" } },
      ],
      ["cancel_production_order", { order_id: "mo2", reason: "Dropped" }],
      [
        "list_production_orders",
        { tenant: "org-1", filter: { status: "done", limit: 10 } },
      ],
    ]);
  });

  it("refuses extra fields the schema rejects before calling", async () => {
    const t = fieldsTransport({});

    const manufacturing = createManufacturing({
      transport: t,
      tenant: "org-1",
      fields: Fields,
    });

    const result = await manufacturing.createOrder({
      variantId: "bread",
      quantity: 1,
      // SAFETY: the test passes a value the fields schema refuses.
      fields: { line: "east" } as unknown as { line: "north" },
    });

    expect(result.ok).toBe(false);
    expect(t.calls).toEqual([]);
  });

  it("traces lots and plans material requirements", async () => {
    const t = fieldsTransport({
      lot_genealogy: () => ({
        lotId: "lot-bread",
        direction: "down",
        lots: [
          {
            level: 1,
            lotId: "lot-flour",
            code: "F1",
            variantId: "flour",
            expiresOn: null,
            fromLotId: "lot-bread",
            orderId: "mo1",
            quantity: "2.040000",
          },
        ],
      }),
      lot_recall: () => ({
        lotId: "lot-flour",
        lots: [{ lotId: "lot-flour", code: "F1", variantId: "flour" }],
        stock: [
          {
            lotId: "lot-flour",
            variantId: "flour",
            locationId: "l1",
            binId: null,
            onHand: "7.960000",
          },
        ],
        documents: [
          {
            referenceType: "order",
            referenceId: "so1",
            lotId: "lot-flour",
            variantId: "flour",
            quantity: "1",
            at: AT,
          },
        ],
        orders: [
          {
            orderId: "mo1",
            number: "MO-2026-0001",
            status: "done",
            variantId: "bread",
            outputLotId: "lot-bread",
          },
        ],
      }),
      material_requirements: () => ({
        organizationId: "org-1",
        horizonDays: 14,
        items: [
          {
            variantId: "flour",
            action: "purchase",
            bomId: null,
            quantity: "17.000",
            available: "8",
            incoming: "0",
            planned: "0",
            demand: "25",
            reorderPoint: null,
          },
        ],
      }),
      create_from_requirements: () => ({
        productionOrders: [{ ...ORDER, status: "draft" }],
        purchaseOrders: [{ id: "po1" }],
      }),
    });

    const manufacturing = createManufacturing({
      transport: t,
      tenant: "org-1",
    });

    const genealogy = await manufacturing
      .lotGenealogy({ lotId: "lot-bread" })
      .orThrow();

    const recall = await manufacturing.lotRecall("lot-flour").orThrow();
    const requirements = await manufacturing.requirements(14).orThrow();

    const documents = await manufacturing
      .createFromRequirements([
        { variantId: "bread", action: "produce", quantity: 10 },
        {
          variantId: "flour",
          action: "purchase",
          quantity: 17,
          supplier: { type: "supplier", id: "s1" },
          unitCost: money(200, "EUR"),
        },
      ])
      .orThrow();

    expect(genealogy.lots[0]).toMatchObject({ code: "F1", quantity: 2.04 });
    expect(recall.stock[0]?.onHand).toBe(7.96);
    expect(recall.documents[0]?.at.toString()).toBe(AT);
    expect(recall.orders[0]?.outputLotId).toBe("lot-bread");
    expect(requirements.items[0]).toMatchObject({
      action: "purchase",
      quantity: 17,
      demand: 25,
    });
    expect(requirements.items[0]?.reorderPoint).toBeUndefined();
    expect(documents.purchaseOrders).toEqual([{ id: "po1" }]);
    expect(documents.purchaseRequisitions).toEqual([]);
    expect(documents.productionOrders[0]?.status).toBe("draft");
    expect(t.calls.map(([fn, args]) => [fn, args])).toEqual([
      ["lot_genealogy", { lot_id: "lot-bread", direction: "down" }],
      ["lot_recall", { lot_id: "lot-flour" }],
      ["material_requirements", { tenant: "org-1", horizon_days: 14 }],
      [
        "create_from_requirements",
        {
          tenant: "org-1",
          items: [
            { variantId: "bread", action: "produce", quantity: 10 },
            {
              variantId: "flour",
              action: "purchase",
              quantity: 17,
              supplierType: "supplier",
              supplierId: "s1",
              unitCost: "200",
              currency: "EUR",
            },
          ],
        },
      ],
    ]);
  });

  it("needs a tenant for organization-wide calls", async () => {
    const manufacturing = createManufacturing({
      transport: fieldsTransport({}),
    });

    const result = await manufacturing.listOrders();

    expect(result.ok).toBe(false);
  });
});

describe("manufacturing schemas and manifest", () => {
  it("validates the inputs", () => {
    expect(
      validate(bomInputSchema, {
        components: [{ variantId: "flour", quantity: 0.5 }],
      }).issues,
    ).toBeUndefined();
    expect(validate(bomInputSchema, { quantity: 1 }).issues).toBeDefined();
    expect(
      validate(workCenterInputSchema, { name: "Oven" }).issues,
    ).toBeUndefined();
    expect(
      validate(productionOrderInputSchema, { variantId: "bread", quantity: 1 })
        .issues,
    ).toBeDefined();
  });

  it("declares the block", () => {
    expect(manufacturingBlock).toMatchObject({
      name: "manufacturing",
      sql: ["manufacturing"],
      category: "commerce",
    });
  });
});
