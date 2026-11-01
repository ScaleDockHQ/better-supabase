import { describe, expect, it } from "vitest";

import type { RouteOptimizer } from "../../../src/blocks/dispatch/route-optimizer.ts";

import {
  binSlotInputSchema,
  countPlanInputSchema,
  createWarehouse,
  pickRecordSchema,
  putawayRequestSchema,
  putawayRuleInputSchema,
  slottingOptionsSchema,
  warehouseBlock,
} from "../../../src/blocks/warehouse/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-29T10:00:00Z";

const WAVE = {
  id: "w1",
  organizationId: "org-1",
  name: "Morning",
  locationId: "l1",
  status: "released",
  releasedAt: AT,
  createdAt: AT,
  lists: 2,
  openLists: 1,
};

const LIST = {
  id: "p1",
  organizationId: "org-1",
  waveId: "w1",
  locationId: "l1",
  documentType: "sales_order",
  documentId: "SO-1",
  status: "open",
  assigneeId: "u1",
  taskId: "t1",
  createdAt: AT,
  lines: [
    {
      id: "n1",
      allocationId: "a1",
      variantId: "v1",
      binId: "b1",
      lotId: "o1",
      serials: ["S1"],
      quantity: "3.000000",
      picked: "1.000000",
      status: "open",
      pickedAt: AT,
      pickedBy: "u1",
    },
    {
      id: "n2",
      allocationId: "a2",
      variantId: "v2",
      quantity: "1.000000",
      picked: "0.000000",
      status: "short",
    },
  ],
};

const PLAN = {
  id: "c1",
  organizationId: "org-1",
  name: "Aisle 1",
  locationId: "l1",
  everyDays: 30,
  variantIds: ["v1"],
  varianceLimitPct: "5.00",
  nextRunOn: "2026-11-01",
  lastRunAt: AT,
  lastCountId: "k1",
  active: true,
  createdAt: AT,
  countId: "k2",
};

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createWarehouse", () => {
  it("creates, releases, cancels and lists waves", async () => {
    const t = fieldsTransport({
      create_pick_wave: () => ({ ...WAVE, status: "draft" }),
      release_pick_wave: () => WAVE,
      cancel_pick_wave: () => ({ ...WAVE, status: "cancelled" }),
      list_pick_waves: () => [WAVE, { ...WAVE, releasedAt: undefined }],
    });

    const warehouse = createWarehouse({ transport: t, tenant: "org-1" });

    const created = await warehouse
      .createPickWave({ name: "Morning", locationId: "l1" })
      .orThrow();

    const released = await warehouse.releasePickWave("w1").orThrow();
    const cancelled = await warehouse.cancelPickWave("w1").orThrow();
    const listed = await warehouse.listPickWaves().orThrow();

    expect(created.status).toBe("draft");
    expect(released.releasedAt?.toString()).toBe(AT);
    expect(released).toMatchObject({ lists: 2, openLists: 1 });
    expect(cancelled.status).toBe("cancelled");
    expect(listed[1]?.releasedAt).toBeUndefined();
    expect(t.calls[0]).toEqual([
      "create_pick_wave",
      { tenant: "org-1", input: { name: "Morning", locationId: "l1" } },
    ]);
  });

  it("makes, picks, completes and reads pick lists", async () => {
    const t = fieldsTransport({
      create_pick_list: () => LIST,
      record_pick: () => LIST,
      complete_pick_list: () => ({ ...LIST, status: "picked", pickedAt: AT }),
      get_pick_list: () => LIST,
      list_pick_lists: () => [LIST],
    });

    const warehouse = createWarehouse({ transport: t, tenant: "org-1" });

    const made = await warehouse
      .createPickList({
        locationId: "l1",
        documentType: "sales_order",
        documentId: "SO-1",
        waveId: "w1",
      })
      .orThrow();

    await warehouse
      .recordPick("n1", { quantity: 1, binId: "b1", serials: ["S1"] })
      .orThrow();

    const done = await warehouse.completePickList("p1").orThrow();
    const one = await warehouse.getPickList("p1").orThrow();

    const mine = await warehouse
      .listPickLists({ mine: true, status: "open" })
      .orThrow();

    expect(made.lines[0]).toMatchObject({
      binId: "b1",
      serials: ["S1"],
      quantity: "3.000000",
    });
    expect(made.lines[1]?.binId).toBeUndefined();
    expect(made.lines[1]?.status).toBe("short");
    expect(made.taskId).toBe("t1");
    expect(done.status).toBe("picked");
    expect(one.id).toBe("p1");
    expect(mine).toHaveLength(1);
    expect(t.calls).toContainEqual([
      "record_pick",
      { line_id: "n1", attrs: { quantity: 1, binId: "b1", serials: ["S1"] } },
    ]);
    expect(t.calls).toContainEqual([
      "list_pick_lists",
      { tenant: "org-1", filters: { mine: true, status: "open" } },
    ]);
  });

  it("plans counts, runs them and posts with an approval", async () => {
    const t = fieldsTransport({
      create_count_plan: () => PLAN,
      list_count_plans: () => [PLAN, { ...PLAN, variantIds: undefined }],
      run_count_plan: () => PLAN,
      run_due_count_plans: () => [{ planId: "c1", countId: "k2" }],
      get_cycle_count_variance: () => ({
        countId: "k2",
        planId: "c1",
        limitPct: "5.00",
        maxVariancePct: "12.50",
        overLimit: true,
        lines: [
          {
            lineId: "m1",
            variantId: "v1",
            expected: "8.000000",
            counted: "7.000000",
            variance: "-1.000000",
            variancePct: "12.50",
          },
        ],
      }),
      post_cycle_count: () => ({ posted: true, approved: true }),
    });

    const warehouse = createWarehouse({ transport: t, tenant: "org-1" });

    const plan = await warehouse
      .createCountPlan({ name: "Aisle 1", locationId: "l1", everyDays: 30 })
      .orThrow();

    const plans = await warehouse.listCountPlans().orThrow();
    const run = await warehouse.runCountPlan("c1").orThrow();
    const due = await warehouse.runDueCountPlans().orThrow();
    const variance = await warehouse.cycleCountVariance("k2").orThrow();

    const posted = await warehouse
      .postCycleCount("k2", { approve: true })
      .orThrow();

    await warehouse.postCycleCount("k2").orThrow();

    expect(plan).toMatchObject({ everyDays: 30, varianceLimitPct: "5.00" });
    expect(plans[1]?.variantIds).toEqual([]);
    expect(run.countId).toBe("k2");
    expect(due).toEqual([{ planId: "c1", countId: "k2" }]);
    expect(variance.overLimit).toBe(true);
    expect(variance.lines[0]?.variancePct).toBe("12.50");
    expect(posted).toMatchObject({ approved: true });
    expect(t.calls).toContainEqual([
      "post_cycle_count",
      { count_id: "k2", approve: true },
    ]);
    expect(t.calls.at(-1)).toEqual([
      "post_cycle_count",
      { count_id: "k2", approve: false },
    ]);
  });

  it("rejects an unknown status", async () => {
    const t = fieldsTransport({
      get_pick_list: () => ({ ...LIST, status: "lost" }),
    });

    const warehouse = createWarehouse({ transport: t, tenant: "org-1" });

    await expect(warehouse.getPickList("p1").orThrow()).rejects.toThrow(/./);
  });

  it("has a manifest and input schemas with the SQL bounds", () => {
    expect(warehouseBlock.name).toBe("warehouse");
    expect(
      validate(countPlanInputSchema, {
        name: "A",
        locationId: "6f9619ff-8b86-4011-b42d-00c04fc964ff",
        everyDays: 7,
      }).issues,
    ).toBeUndefined();
    expect(
      validate(countPlanInputSchema, {
        name: "A",
        locationId: "6f9619ff-8b86-4011-b42d-00c04fc964ff",
        everyDays: 0,
      }).issues,
    ).toBeDefined();
    expect(validate(pickRecordSchema, { quantity: 2 }).issues).toBeUndefined();
  });
});

const L1 = "6f9619ff-8b86-4011-b42d-00c04fc964ff";

const RULE = {
  id: "r1",
  organizationId: "org-1",
  locationId: "l1",
  binId: "b1",
  variantId: "v1",
  priority: 5,
  maxQuantity: "20.000000",
  active: true,
  createdAt: AT,
};

const SUGGESTION = {
  locationId: "l1",
  variantId: "v1",
  quantity: "8.000000",
  unassigned: "0.000000",
  placements: [
    {
      binId: "b1",
      binCode: "A1",
      quantity: "5.000000",
      source: "rule",
      ruleId: "r1",
    },
    { binId: "b2", binCode: "B1", quantity: "3.000000", source: "free" },
  ],
};

describe("warehouse putaway, slotting and routes", () => {
  it("saves, lists and deletes putaway rules and slots", async () => {
    const t = fieldsTransport({
      save_putaway_rule: () => RULE,
      list_putaway_rules: () => [
        RULE,
        { ...RULE, variantId: undefined, maxQuantity: undefined },
      ],
      delete_putaway_rule: (args) => args["rule_id"] === "r1",
      save_bin_slot: () => ({ binId: "b1", walkRank: 3 }),
      save_variant_size: () => ({ variantId: "v1", size: "2.000000" }),
      list_bin_slots: () => [
        {
          binId: "b1",
          code: "A1",
          locationId: "l1",
          hold: false,
          active: true,
          used: "4.000000",
          walkRank: 3,
          capacity: "10.000000",
        },
        {
          binId: "b2",
          code: "B1",
          locationId: "l1",
          hold: true,
          active: true,
          used: "0.000000",
        },
      ],
    });

    const warehouse = createWarehouse({ transport: t, tenant: "org-1" });

    const rule = await warehouse
      .savePutawayRule({ binId: "b1", variantId: "v1", priority: 5 })
      .orThrow();

    const rules = await warehouse
      .listPutawayRules({ locationId: "l1" })
      .orThrow();

    const gone = await warehouse.deletePutawayRule("r1").orThrow();
    const missing = await warehouse.deletePutawayRule("r9").orThrow();

    const slot = await warehouse
      .saveBinSlot({ binId: "b1", walkRank: 3 })
      .orThrow();

    const size = await warehouse
      .saveVariantSize({ variantId: "v1", size: 2 })
      .orThrow();

    const slots = await warehouse.listBinSlots("l1").orThrow();

    expect(rule).toMatchObject({ priority: 5, maxQuantity: "20.000000" });
    expect(rules[1]?.variantId).toBeUndefined();
    expect(gone).toBe(true);
    expect(missing).toBe(false);
    expect(slot).toEqual({ binId: "b1", walkRank: 3 });
    expect(size.size).toBe("2.000000");
    expect(slots[0]).toMatchObject({ walkRank: 3, capacity: "10.000000" });
    expect(slots[1]?.walkRank).toBeUndefined();
    expect(slots[1]?.hold).toBe(true);
    expect(t.calls[0]).toEqual([
      "save_putaway_rule",
      { tenant: "org-1", input: { binId: "b1", variantId: "v1", priority: 5 } },
    ]);
  });

  it("suggests putaway and slotting", async () => {
    const t = fieldsTransport({
      suggest_putaway: () => SUGGESTION,
      suggest_receipt_putaway: () => [SUGGESTION],
      suggest_slotting: () => [
        {
          variantId: "v1",
          velocity: "12.000000",
          picks: 4,
          onHand: "8.000000",
          action: "move",
          currentBinId: "b2",
          suggestedBinId: "b1",
        },
        {
          variantId: "v2",
          velocity: "0.000000",
          picks: 0,
          onHand: "1.000000",
          action: "keep",
        },
      ],
    });

    const warehouse = createWarehouse({ transport: t, tenant: "org-1" });

    const one = await warehouse
      .suggestPutaway({ locationId: "l1", variantId: "v1", quantity: 8 })
      .orThrow();

    const receipt = await warehouse.suggestReceiptPutaway("rc1").orThrow();

    const slotting = await warehouse
      .suggestSlotting({ locationId: "l1", days: 7 })
      .orThrow();

    expect(one.placements[0]).toMatchObject({ source: "rule", ruleId: "r1" });
    expect(one.placements[1]?.ruleId).toBeUndefined();
    expect(receipt).toHaveLength(1);
    expect(slotting[0]).toMatchObject({ action: "move", suggestedBinId: "b1" });
    expect(slotting[1]?.suggestedBinId).toBeUndefined();
  });

  it("rejects an unknown placement source", async () => {
    const t = fieldsTransport({
      suggest_putaway: () => ({
        ...SUGGESTION,
        placements: [
          { binId: "b", binCode: "A", quantity: "1", source: "luck" },
        ],
      }),
    });

    const warehouse = createWarehouse({ transport: t, tenant: "org-1" });

    await expect(
      warehouse
        .suggestPutaway({ locationId: "l1", variantId: "v1", quantity: 1 })
        .orThrow(),
    ).rejects.toThrow(/./);
  });

  it("orders a pick list by the bins' places and saves the route", async () => {
    const lines = ["n1", "n2", "n3", "n4"].map((id, index) => ({
      ...LIST.lines[0],
      id,
      binId: `b${index + 1}`,
      status: "open",
    }));

    const t = fieldsTransport({
      get_pick_list: () => ({ ...LIST, lines }),
      set_pick_route: () => ({ ...LIST, lines }),
    });

    const warehouse = createWarehouse({ transport: t, tenant: "org-1" });
    const places: Record<string, number> = { b1: 5, b2: 1, b3: 3 };

    const routed = await warehouse
      .optimizePickRoute("p1", {
        locate: (line) => {
          const east = places[line.binId ?? ""];

          return east === undefined
            ? undefined
            : { latitude: 0, longitude: east };
        },
        start: { latitude: 0, longitude: 0 },
      })
      .orThrow();

    expect(routed.optimization.order).toEqual(["n2", "n3", "n1"]);
    expect(t.calls.at(-1)).toEqual([
      "set_pick_route",
      { pick_list_id: "p1", line_ids: ["n2", "n3", "n1", "n4"] },
    ]);
  });

  it("falls back to nearest neighbour when the optimizer fails", async () => {
    const failing: RouteOptimizer = {
      apiVersion: 1,
      name: "broken",
      optimize: () => Promise.reject(new Error("down")),
    };

    const t = fieldsTransport({
      get_pick_list: () => LIST,
      set_pick_route: () => LIST,
    });

    const warehouse = createWarehouse({ transport: t, tenant: "org-1" });

    const routed = await warehouse
      .optimizePickRoute("p1", {
        optimizer: failing,
        locate: () => ({ latitude: 1, longitude: 1 }),
        end: { latitude: 0, longitude: 0 },
      })
      .orThrow();

    expect(routed.optimization.source).toBe("fallback");
    expect(routed.optimization.fallbackReason).toBeDefined();
  });

  it("sets a route by line ids", async () => {
    const t = fieldsTransport({ set_pick_route: () => LIST });
    const warehouse = createWarehouse({ transport: t, tenant: "org-1" });

    await warehouse.setPickRoute("p1", ["n2", "n1"]).orThrow();

    expect(t.calls[0]).toEqual([
      "set_pick_route",
      { pick_list_id: "p1", line_ids: ["n2", "n1"] },
    ]);
  });

  it("has input schemas with the SQL bounds", () => {
    expect(
      validate(putawayRuleInputSchema, { binId: L1, priority: 10_001 }).issues,
    ).toBeDefined();
    expect(
      validate(putawayRuleInputSchema, { binId: L1, priority: 3 }).issues,
    ).toBeUndefined();
    expect(
      validate(binSlotInputSchema, { binId: L1, walkRank: 100_001 }).issues,
    ).toBeDefined();
    expect(
      validate(putawayRequestSchema, {
        locationId: L1,
        variantId: L1,
        quantity: 2,
      }).issues,
    ).toBeUndefined();
    expect(
      validate(slottingOptionsSchema, { locationId: L1, days: 0 }).issues,
    ).toBeDefined();
  });
});
