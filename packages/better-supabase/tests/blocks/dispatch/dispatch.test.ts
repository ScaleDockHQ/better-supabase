import { describe, expect, it } from "vitest";

import {
  createDispatch,
  dispatchBlock,
  dispatchBinding,
  workOrderInputSchema,
  workOrderPartInputSchema,
  workOrderSectionInputSchema,
} from "../../../src/blocks/dispatch/index.ts";

const AT = "2026-10-22T08:00:00Z";
const END = "2026-10-22T09:00:00Z";

const ORDER = {
  id: "w1",
  organizationId: "org-1",
  title: "Fix the boiler",
  description: "Pressure drops at night",
  priority: "high",
  status: "scheduled",
  technicianId: "t1",
  startsAt: AT,
  endsAt: END,
  day: "2026-10-22",
  locationId: "l1",
  assetId: "a1",
  bookingId: "b1",
  subjectType: "customer",
  subjectId: "c1",
  address: "Main St 1",
  enRouteAt: AT,
  arrivedAt: AT,
  completedAt: END,
  cancelledAt: END,
  cancelReason: "duplicate",
  completionNote: "replaced valve",
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
  fields: { region: "north" },
};

const BARE = {
  id: "w2",
  organizationId: "org-1",
  title: "Inspect",
  description: null,
  priority: "normal",
  status: "unscheduled",
  technicianId: null,
  startsAt: null,
  endsAt: null,
  day: null,
  locationId: null,
  assetId: null,
  bookingId: null,
  subjectType: null,
  subjectId: null,
  address: null,
  enRouteAt: null,
  arrivedAt: null,
  completedAt: null,
  cancelledAt: null,
  cancelReason: null,
  completionNote: null,
  createdBy: null,
  createdAt: AT,
  updatedAt: AT,
};

const PART = {
  id: "p1",
  organizationId: "org-1",
  workOrderId: "w1",
  name: "Valve",
  quantity: "2.000",
  unit: "pcs",
  assetId: "a1",
  variantId: "v1",
  locationId: "l1",
  recordedBy: "t1",
  createdAt: AT,
};

const BARE_PART = {
  ...PART,
  id: "p2",
  unit: null,
  assetId: null,
  variantId: null,
  locationId: null,
  recordedBy: null,
};

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    transport: {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([fn, { ...args }]);

        return Promise.resolve(results[fn]);
      },
    },
  };
}

const instant = (value: string) => Temporal.Instant.from(value);

describe("createDispatch", () => {
  it("creates a scheduled work order in the block's tenant", async () => {
    const fake = fakeTransport({ create_work_order: ORDER });

    const dispatch = createDispatch({
      transport: fake.transport,
      tenant: "org-1",
    });

    const order = await dispatch
      .create({
        title: "Fix the boiler",
        priority: "high",
        subject: { type: "customer", id: "c1" },
        technicianId: "t1",
        startsAt: instant(AT),
        endsAt: instant(END),
        assetId: "a1",
        locationId: "l1",
        bookingId: "b1",
        address: "Main St 1",
        description: "Pressure drops at night",
      })
      .orThrow();

    expect(fake.calls[0]).toEqual([
      "create_work_order",
      {
        tenant: "org-1",
        title: "Fix the boiler",
        description: "Pressure drops at night",
        priority: "high",
        location_id: "l1",
        asset_id: "a1",
        booking_id: "b1",
        subject_type: "customer",
        subject_id: "c1",
        address: "Main St 1",
        technician: "t1",
        starts_at: AT,
        ends_at: END,
      },
    ]);
    expect(order.status).toBe("scheduled");
    expect(order.subject).toEqual({ type: "customer", id: "c1" });
    expect(order.day?.toString()).toBe("2026-10-22");
    expect(order.startsAt?.toString()).toBe(AT);
    expect(order.completionNote).toBe("replaced valve");
    expect(order.fields).toEqual({ region: "north" });
  });

  it("defaults the optional inputs and leaves absent values out", async () => {
    const fake = fakeTransport({ create_work_order: BARE });

    const dispatch = createDispatch({
      transport: fake.transport,
      tenant: "org-1",
    });

    const order = await dispatch.create({ title: "Inspect" }).orThrow();

    expect(fake.calls[0]?.[1]).toMatchObject({
      priority: "normal",
      description: null,
      technician: null,
      starts_at: null,
      ends_at: null,
      subject_type: null,
    });
    expect(order).not.toHaveProperty("technicianId");
    expect(order).not.toHaveProperty("day");
    expect(order).not.toHaveProperty("subject");
    expect(order.fields).toEqual({});
  });

  it("fails without a tenant for tenant-wide calls", async () => {
    const dispatch = createDispatch({ transport: fakeTransport({}).transport });

    const result = await dispatch.list();

    expect(result.ok).toBe(false);
  });

  it("validates and returns extra fields through the schema", async () => {
    const fake = fakeTransport({ update_work_order: ORDER });

    const schema = {
      "~standard": {
        version: 1 as const,
        vendor: "test",
        validate: (value: unknown) =>
          typeof value === "object" && value !== null && "region" in value
            ? { value: value as { region: string } }
            : { issues: [{ message: "region is required" }] },
      },
    };

    const dispatch = createDispatch({
      transport: fake.transport,
      tenant: "org-1",
      fields: schema,
    });

    const order = await dispatch
      .update("w1", { title: "Fix it", fields: { region: "north" } })
      .orThrow();

    expect(order.fields.region).toBe("north");
    expect(fake.calls[0]).toEqual([
      "update_work_order",
      {
        work_order_id: "w1",
        title: "Fix it",
        description: null,
        priority: null,
        location_id: null,
        asset_id: null,
        address: null,
        fields: { region: "north" },
      },
    ]);
  });

  it("schedules, unschedules and moves a work order on", async () => {
    const fake = fakeTransport({
      schedule_work_order: ORDER,
      unschedule_work_order: BARE,
      set_work_order_status: { ...ORDER, status: "done" },
    });

    const dispatch = createDispatch({ transport: fake.transport });

    await dispatch
      .schedule("w1", { technicianId: "t1", startsAt: instant(AT) })
      .orThrow();
    await dispatch.unschedule("w1").orThrow();
    const done = await dispatch.setStatus("w1", "done", "fixed").orThrow();
    await dispatch.setStatus("w1", "en_route").orThrow();

    expect(done.status).toBe("done");
    expect(fake.calls).toEqual([
      [
        "schedule_work_order",
        { work_order_id: "w1", technician: "t1", starts_at: AT, ends_at: null },
      ],
      ["unschedule_work_order", { work_order_id: "w1" }],
      [
        "set_work_order_status",
        { work_order_id: "w1", status: "done", note: "fixed" },
      ],
      [
        "set_work_order_status",
        { work_order_id: "w1", status: "en_route", note: null },
      ],
    ]);
  });

  it("returns null for a work order it can't read", async () => {
    const fake = fakeTransport({ get_work_order: null });
    const dispatch = createDispatch({ transport: fake.transport });

    expect(await dispatch.get("w9").orThrow()).toBeNull();

    const found = createDispatch({
      transport: fakeTransport({ get_work_order: ORDER }).transport,
    });

    expect((await found.get("w1").orThrow())?.id).toBe("w1");
  });

  it("lists with filters and defaults", async () => {
    const fake = fakeTransport({ list_work_orders: [ORDER, BARE] });

    const dispatch = createDispatch({
      transport: fake.transport,
      tenant: "org-1",
    });

    const orders = await dispatch
      .list({
        status: "scheduled",
        technicianId: "t1",
        subject: { type: "customer", id: "c1" },
        from: instant(AT),
        until: instant(END),
        before: instant(END),
        limit: 10,
      })
      .orThrow();

    await dispatch.list().orThrow();

    expect(orders.map((order) => order.id)).toEqual(["w1", "w2"]);
    expect(fake.calls[0]?.[1]).toEqual({
      tenant: "org-1",
      status: "scheduled",
      technician: "t1",
      subject_type: "customer",
      subject_id: "c1",
      from_at: AT,
      until_at: END,
      before: END,
      page_size: 10,
    });
    expect(fake.calls[1]?.[1]).toMatchObject({ status: null, page_size: 50 });
  });

  it("reads the schedule board", async () => {
    const fake = fakeTransport({
      dispatch_board: {
        from: "2026-10-22",
        to: "2026-10-23",
        timeZone: "Europe/Amsterdam",
        technicianIds: ["t1"],
        scheduled: [ORDER],
        backlog: [BARE],
      },
    });

    const dispatch = createDispatch({
      transport: fake.transport,
      tenant: "org-1",
    });

    const board = await dispatch
      .board({
        from: Temporal.PlainDate.from("2026-10-22"),
        to: Temporal.PlainDate.from("2026-10-23"),
        technicianIds: ["t1"],
      })
      .orThrow();

    await dispatch
      .board({
        from: Temporal.PlainDate.from("2026-10-22"),
        to: Temporal.PlainDate.from("2026-10-22"),
      })
      .orThrow();

    expect(board.timeZone).toBe("Europe/Amsterdam");
    expect(board.to.toString()).toBe("2026-10-23");
    expect(board.technicianIds).toEqual(["t1"]);
    expect(board.scheduled[0]?.id).toBe("w1");
    expect(board.backlog[0]?.id).toBe("w2");
    expect(fake.calls[0]?.[1]).toEqual({
      tenant: "org-1",
      from_date: "2026-10-22",
      to_date: "2026-10-23",
      technicians: ["t1"],
    });
    expect(fake.calls[1]?.[1]).toMatchObject({ technicians: null });
  });

  it("reads a technician's day with and without a route", async () => {
    const fake = fakeTransport({
      technician_day: {
        technicianId: "t1",
        date: "2026-10-22",
        routeId: "r1",
        stops: [{ position: 1, workOrder: ORDER }],
      },
    });

    const dispatch = createDispatch({
      transport: fake.transport,
      tenant: "org-1",
    });

    const day = Temporal.PlainDate.from("2026-10-22");

    const plan = await dispatch.technicianDay(day, "t1").orThrow();

    expect(plan.routeId).toBe("r1");
    expect(plan.stops[0]?.position).toBe(1);
    expect(plan.stops[0]?.workOrder.id).toBe("w1");
    expect(fake.calls[0]?.[1]).toEqual({
      tenant: "org-1",
      day: "2026-10-22",
      technician: "t1",
    });

    const empty = createDispatch({
      transport: fakeTransport({
        technician_day: {
          technicianId: "t1",
          date: "2026-10-22",
          routeId: null,
          stops: [],
        },
      }).transport,
      tenant: "org-1",
    });

    const own = await empty.technicianDay(day).orThrow();

    expect(own).not.toHaveProperty("routeId");
    expect(own.stops).toEqual([]);
  });

  it("plans a route", async () => {
    const fake = fakeTransport({
      plan_dispatch_route: {
        id: "r1",
        organizationId: "org-1",
        technicianId: "t1",
        routeDate: "2026-10-22",
        stops: ["w2", "w1"],
      },
    });

    const dispatch = createDispatch({
      transport: fake.transport,
      tenant: "org-1",
    });

    const route = await dispatch
      .planRoute("t1", Temporal.PlainDate.from("2026-10-22"), ["w2", "w1"])
      .orThrow();

    expect(route.workOrderIds).toEqual(["w2", "w1"]);
    expect(route.routeDate.toString()).toBe("2026-10-22");
    expect(fake.calls[0]?.[1]).toEqual({
      tenant: "org-1",
      technician: "t1",
      route_date: "2026-10-22",
      work_orders: ["w2", "w1"],
    });
  });

  it("optimizes a route and plans it, with stops without a place last", async () => {
    const at = (id: string): typeof ORDER => ({ ...ORDER, id });

    const fake = fakeTransport({
      technician_day: {
        technicianId: "t1",
        date: "2026-10-22",
        routeId: null,
        stops: [
          { position: 1, workOrder: at("far") },
          { position: 2, workOrder: at("nowhere") },
          { position: 3, workOrder: at("near") },
        ],
      },
      plan_dispatch_route: {
        id: "r1",
        organizationId: "org-1",
        technicianId: "t1",
        routeDate: "2026-10-22",
        stops: ["near", "far", "nowhere"],
      },
    });

    const dispatch = createDispatch({
      transport: fake.transport,
      tenant: "org-1",
    });

    const points: Record<string, { latitude: number; longitude: number }> = {
      far: { latitude: 52.5, longitude: 5.5 },
      near: { latitude: 52.01, longitude: 5.01 },
    };

    const result = await dispatch
      .optimizeRoute("t1", Temporal.PlainDate.from("2026-10-22"), {
        locate: (order) => points[order.id],
        start: { latitude: 52, longitude: 5 },
        end: { latitude: 52, longitude: 5 },
        durationMinutes: () => 30,
      })
      .orThrow();

    expect(result.optimization.source).toBe("optimizer");
    expect(result.route.workOrderIds).toEqual(["near", "far", "nowhere"]);
    expect(fake.calls[1]?.[1]).toMatchObject({
      work_orders: ["near", "far", "nowhere"],
    });

    await dispatch
      .optimizeRoute("t1", Temporal.PlainDate.from("2026-10-22"), {
        locate: (order) => points[order.id],
        optimizer: {
          apiVersion: 1,
          name: "custom",
          optimize: (request) =>
            Promise.resolve({
              order: request.stops.map((stop) => stop.id).toReversed(),
            }),
        },
      })
      .orThrow();

    expect(fake.calls[3]?.[1]).toMatchObject({
      work_orders: ["near", "far", "nowhere"],
    });
  });

  it("records, lists and removes parts", async () => {
    const fake = fakeTransport({
      record_work_order_part: PART,
      list_work_order_parts: [PART, BARE_PART],
      remove_work_order_part: true,
    });

    const dispatch = createDispatch({ transport: fake.transport });

    const part = await dispatch
      .recordPart("w1", {
        name: "Valve",
        quantity: 2,
        unit: "pcs",
        assetId: "a1",
        variantId: "v1",
        locationId: "l1",
      })
      .orThrow();

    await dispatch
      .recordPart("w1", { name: "Tape", quantity: "1.5" })
      .orThrow();
    const parts = await dispatch.parts("w1").orThrow();
    const removed = await dispatch.removePart("p1").orThrow();

    expect(part.quantity).toBe("2.000");
    expect(parts[1]).not.toHaveProperty("unit");
    expect(removed).toBe(true);
    expect(fake.calls[0]?.[1]).toEqual({
      work_order_id: "w1",
      name: "Valve",
      quantity: "2",
      unit: "pcs",
      asset_id: "a1",
      variant_id: "v1",
      location_id: "l1",
    });
    expect(fake.calls[1]?.[1]).toMatchObject({
      quantity: "1.5",
      unit: null,
      asset_id: null,
    });
  });

  it("refuses a row with an unknown status", async () => {
    const dispatch = createDispatch({
      transport: fakeTransport({ get_work_order: { ...ORDER, status: "lost" } })
        .transport,
    });

    expect((await dispatch.get("w1")).ok).toBe(false);
  });
});

describe("dispatch block", () => {
  it("declares its SQL module, events, section and recipes", () => {
    expect(dispatchBlock.name).toBe("dispatch");
    expect(dispatchBlock.sql).toEqual(["dispatch"]);
    expect(dispatchBlock.recipes).toEqual(["dispatch-board", "technician-day"]);
    expect(dispatchBlock.record).toBeDefined();
  });

  it("validates the inputs with the bounds the SQL checks", async () => {
    const ok = await workOrderInputSchema["~standard"].validate({
      title: "Fix",
      priority: "urgent",
    });

    const bad = await workOrderInputSchema["~standard"].validate({
      title: "",
      priority: "whenever",
    });

    const part = await workOrderPartInputSchema["~standard"].validate({
      name: "Valve",
      quantity: 1,
    });

    const section = await workOrderSectionInputSchema["~standard"].validate({
      title: "Fix",
    });

    expect(ok.issues).toBeUndefined();
    expect(bad.issues?.length).toBeGreaterThan(0);
    expect(part.issues).toBeUndefined();
    expect(section.issues).toBeUndefined();
  });

  it("loads and writes the work orders of a record", async () => {
    const fake = fakeTransport({
      list_work_orders: [ORDER],
      create_work_order: ORDER,
      set_work_order_status: { ...ORDER, status: "cancelled" },
    });

    const dispatch = createDispatch({
      transport: fake.transport,
      tenant: "org-1",
    });

    const subject = { type: "customer", id: "c1" };

    const rows = await dispatchBinding
      .load(dispatch, subject, undefined)
      .orThrow();

    await dispatchBinding.writes.create
      .run(dispatch, subject, { title: "Fix" })
      .orThrow();

    const cancelled = await dispatchBinding.writes.cancel
      .run(dispatch, subject, { id: "w1" })
      .orThrow();

    expect(rows[0]?.id).toBe("w1");
    expect(cancelled.status).toBe("cancelled");
    expect(fake.calls.map(([fn]) => fn)).toEqual([
      "list_work_orders",
      "create_work_order",
      "set_work_order_status",
    ]);
    expect(fake.calls[1]?.[1]).toMatchObject({
      subject_type: "customer",
      subject_id: "c1",
    });
  });
});
