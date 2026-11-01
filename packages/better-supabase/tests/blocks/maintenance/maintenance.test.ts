import { describe, expect, it } from "vitest";

import {
  createMaintenance,
  maintenanceBlock,
  maintenanceCalibrationInputSchema,
  maintenancePlanInputSchema,
} from "../../../src/blocks/maintenance/index.ts";
import { temporal } from "../../../src/core/temporal-required.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-29T10:00:00Z";

const PLAN = {
  id: "p1",
  organizationId: "org-1",
  title: "Grease the press",
  kind: "meter",
  meterId: "m1",
  everyValue: "500",
  priority: "high",
  status: "active",
  due: true,
  parts: [{ id: "x1", name: "Grease", quantity: "2", variantId: "v1" }],
  createdAt: AT,
  updatedAt: AT,
};

const METER = {
  id: "m1",
  organizationId: "org-1",
  name: "Press hours",
  unit: "h",
  reading: "1200",
  readAt: AT,
  createdAt: AT,
};

const CALIBRATION = {
  id: "c1",
  organizationId: "org-1",
  instrument: "Scale",
  performedAt: AT,
  dueAt: "2027-10-29T10:00:00Z",
  result: "pass",
  reference: "CAL-1",
};

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createMaintenance", () => {
  it("creates, updates, lists and deletes plans", async () => {
    const t = fieldsTransport({
      create_maintenance_plan: () => PLAN,
      update_maintenance_plan: () => ({
        ...PLAN,
        status: "paused",
        due: false,
        everyDays: 30,
        assetId: "a1",
        lastDoneAt: AT,
        nextDueAt: AT,
        workOrderId: "w1",
      }),
      delete_maintenance_plan: () => PLAN,
      list_maintenance_plans: () => [PLAN, { ...PLAN, parts: undefined }],
    });

    const maintenance = createMaintenance({ transport: t, tenant: "org-1" });

    const created = await maintenance
      .createPlan({
        title: "Grease the press",
        kind: "meter",
        meterId: "m1",
        everyValue: "500",
        parts: [
          { name: "Grease", quantity: 2, variantId: "v1" },
          { name: "Cloth" },
        ],
      })
      .orThrow();

    const updated = await maintenance
      .updatePlan("p1", { status: "paused" })
      .orThrow();

    const deleted = await maintenance.deletePlan("p1").orThrow();

    const listed = await maintenance
      .listPlans({ due: true, status: "active", limit: 5 })
      .orThrow();

    expect(created.parts).toEqual([
      { id: "x1", name: "Grease", quantity: "2", variantId: "v1" },
    ]);
    expect(created.due).toBe(true);
    expect(updated).toMatchObject({
      status: "paused",
      everyDays: 30,
      assetId: "a1",
      workOrderId: "w1",
    });
    expect(updated.nextDueAt?.toString()).toBe("2026-10-29T10:00:00Z");
    expect(deleted.id).toBe("p1");
    expect(listed).toHaveLength(2);
    expect(listed[1]?.parts).toEqual([]);
    expect(t.calls[0]).toEqual([
      "create_maintenance_plan",
      {
        tenant: "org-1",
        input: {
          title: "Grease the press",
          kind: "meter",
          meterId: "m1",
          everyValue: "500",
          parts: [
            { name: "Grease", quantity: "2", variantId: "v1" },
            { name: "Cloth" },
          ],
        },
      },
    ]);
    expect(t.calls[3]).toEqual([
      "list_maintenance_plans",
      { tenant: "org-1", filters: { status: "active", due: true, limit: 5 } },
    ]);
  });

  it("generates work orders, and handles meters and calibrations", async () => {
    const t = fieldsTransport({
      generate_maintenance_work_orders: () => [
        { planId: "p1", workOrderId: "w1" },
      ],
      create_maintenance_meter: () => METER,
      record_meter_reading: () => METER,
      list_maintenance_meters: () => [{ ...METER, assetId: "a1" }],
      record_calibration: () => CALIBRATION,
      list_calibrations: () => [CALIBRATION],
    });

    const maintenance = createMaintenance({ transport: t, tenant: "org-1" });
    const instant = temporal().Instant.from(AT);

    expect(await maintenance.generateWorkOrders().orThrow()).toEqual([
      { planId: "p1", workOrderId: "w1" },
    ]);
    await maintenance
      .createMeter({ name: "Press hours", unit: "h", assetId: "a1" })
      .orThrow();
    await maintenance.createMeter({ name: "Press hours", unit: "h" }).orThrow();
    await maintenance.recordReading("m1", 1200).orThrow();
    await maintenance.recordReading("m1", "1300", instant).orThrow();
    const meters = await maintenance.listMeters().orThrow();

    const recorded = await maintenance
      .recordCalibration({
        instrument: "Scale",
        performedAt: instant,
        dueAt: instant,
        result: "pass",
        reference: "CAL-1",
      })
      .orThrow();

    const calibrations = await maintenance
      .listCalibrations({ assetId: "a1", dueBefore: instant })
      .orThrow();

    expect(meters[0]?.assetId).toBe("a1");
    expect(meters[0]?.reading).toBe("1200");
    expect(recorded.reference).toBe("CAL-1");
    expect(calibrations).toHaveLength(1);
    expect(t.calls).toContainEqual([
      "record_meter_reading",
      { meter_id: "m1", value: "1300", read_at: AT },
    ]);
    expect(t.calls).toContainEqual([
      "record_meter_reading",
      { meter_id: "m1", value: "1200", read_at: null },
    ]);
    expect(t.calls).toContainEqual([
      "list_calibrations",
      { tenant: "org-1", filters: { assetId: "a1", dueBefore: AT } },
    ]);
  });

  it("lists without options and rejects an unknown kind", async () => {
    const t = fieldsTransport({
      list_maintenance_plans: () => [],
      list_calibrations: () => [],
      list_maintenance_meters: () => [{ ...METER, readAt: undefined }],
      update_maintenance_plan: () => ({ ...PLAN, kind: "weekly" }),
    });

    const maintenance = createMaintenance({ transport: t, tenant: "org-1" });

    expect(await maintenance.listPlans().orThrow()).toEqual([]);
    expect(await maintenance.listCalibrations().orThrow()).toEqual([]);
    expect(
      (await maintenance.listMeters().orThrow())[0]?.readAt,
    ).toBeUndefined();
    await expect(
      maintenance.updatePlan("p1", { title: "x" }).orThrow(),
    ).rejects.toThrow(/./);
  });

  it("sends calendar rule plans and qualifications", async () => {
    const t = fieldsTransport({
      create_maintenance_plan: () => ({
        ...PLAN,
        kind: "rrule",
        rrule: "FREQ=WEEKLY;BYDAY=MO",
        dtstart: AT,
        tz: "Europe/Amsterdam",
        requiredQualifications: ["welder"],
      }),
      record_calibration: () => ({ ...CALIBRATION, qualifications: ["cal"] }),
    });

    const maintenance = createMaintenance({ transport: t, tenant: "org-1" });

    const plan = await maintenance
      .createPlan({
        title: "Weekly check",
        kind: "rrule",
        rrule: "FREQ=WEEKLY;BYDAY=MO",
        dtstart: temporal().Instant.from(AT),
        tz: "Europe/Amsterdam",
        requiredQualifications: ["welder"],
      })
      .orThrow();

    const calibration = await maintenance
      .recordCalibration({
        instrument: "Scale",
        performedAt: temporal().Instant.from(AT),
        dueAt: temporal().Instant.from(AT),
        result: "pass",
        qualifications: ["cal"],
      })
      .orThrow();

    expect(plan.rrule).toBe("FREQ=WEEKLY;BYDAY=MO");
    expect(plan.requiredQualifications).toEqual(["welder"]);
    expect(calibration.qualifications).toEqual(["cal"]);
    expect(
      validate(maintenancePlanInputSchema, {
        title: "Weekly",
        kind: "rrule",
        rrule: "FREQ=DAILY",
        dtstart: temporal().Instant.from(AT),
      }).issues,
    ).toBeUndefined();
  });

  it("has a manifest and input schemas with the SQL bounds", () => {
    expect(maintenanceBlock.name).toBe("maintenance");
    expect(
      validate(maintenancePlanInputSchema, {
        title: "Grease",
        kind: "time",
        everyDays: 30,
      }).issues,
    ).toBeUndefined();
    expect(
      validate(maintenancePlanInputSchema, { title: "", kind: "time" }).issues,
    ).toBeDefined();
    expect(
      validate(maintenanceCalibrationInputSchema, {
        instrument: "Scale",
        performedAt: temporal().Instant.from(AT),
        dueAt: temporal().Instant.from(AT),
        result: "pass",
      }).issues,
    ).toBeUndefined();
    expect(
      validate(maintenanceCalibrationInputSchema, {
        instrument: "Scale",
        performedAt: temporal().Instant.from(AT),
        dueAt: temporal().Instant.from(AT),
        result: "meh",
      }).issues,
    ).toBeDefined();
  });
});
