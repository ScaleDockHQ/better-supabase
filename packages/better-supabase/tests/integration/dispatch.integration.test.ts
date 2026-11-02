import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";

import { createAssets } from "../../src/blocks/assets/index.ts";
import { createDispatch } from "../../src/blocks/dispatch/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = ["organizations", "outbox", "bookings", "assets", "dispatch"];

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

const at = (text: string): Temporal.Instant => Temporal.Instant.from(text);
const DAY = Temporal.PlainDate.from("2030-01-07");

describe.skipIf(!live)("dispatch", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("schedules work orders on a board and works a technician's day", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("dispatcher");
      const tech = await s.user("tech");
      const outsider = await s.user("outsider");
      await s.install(MODULES);
      const tenant = await s.organization(owner, { member: tech });
      await s.organization(outsider);
      const transport = sqlTransport(s.sql);
      const dispatch = createDispatch({ transport, tenant });

      await s.as(owner);

      const site = await createAssets({ transport, tenant })
        .createLocation({ kind: "site", name: "Plant" })
        .orThrow();

      const backlog = await dispatch
        .create({ title: "Service the boiler", locationId: site.id })
        .orThrow();

      const first = await dispatch
        .create({
          title: "Replace the valve",
          technicianId: tech.id,
          startsAt: at("2030-01-07T09:00:00Z"),
        })
        .orThrow();

      expect(backlog.status).toBe("unscheduled");
      expect(first).toMatchObject({
        status: "scheduled",
        technicianId: tech.id,
        endsAt: at("2030-01-07T10:00:00Z"),
      });
      expect(
        await dispatch
          .schedule({
            id: backlog.id,
            slot: {
              technicianId: tech.id,
              startsAt: at("2030-01-07T09:30:00Z"),
            },
          })
          .then(hint),
      ).toBe("DISPATCH_SLOT_TAKEN");
      expect(
        await dispatch
          .schedule({
            id: backlog.id,
            slot: {
              technicianId: outsider.id,
              startsAt: at("2030-01-07T11:00:00Z"),
            },
          })
          .then(hint),
      ).toBe("DISPATCH_TECHNICIAN_INVALID");

      await dispatch
        .schedule({
          id: backlog.id,
          slot: {
            technicianId: tech.id,
            startsAt: at("2030-01-07T11:00:00Z"),
            endsAt: at("2030-01-07T13:00:00Z"),
          },
        })
        .orThrow();

      await dispatch.create({ title: "Inspect the roof", priority: "urgent" });

      const board = await dispatch.board({ from: DAY, to: DAY }).orThrow();

      expect(board.technicianIds).toEqual([tech.id]);
      expect(board.scheduled.map((order) => order.title)).toEqual([
        "Replace the valve",
        "Service the boiler",
      ]);
      expect(board.backlog.map((order) => order.title)).toEqual([
        "Inspect the roof",
      ]);

      const route = await dispatch
        .planRoute({
          technicianId: tech.id,
          day: DAY,
          workOrderIds: [backlog.id, first.id],
        })
        .orThrow();

      expect(route.workOrderIds).toEqual([backlog.id, first.id]);

      await s.as(tech);

      const day = await dispatch.technicianDay({ day: DAY }).orThrow();

      expect(day.routeId).toBe(route.id);
      expect(day.stops.map((stop) => stop.workOrder.id)).toEqual([
        backlog.id,
        first.id,
      ]);

      await dispatch.setStatus({ id: first.id, status: "en_route" }).orThrow();
      expect(
        await dispatch.setStatus({ id: first.id, status: "done" }).then(hint),
      ).toBe("DISPATCH_TRANSITION_INVALID");
      await dispatch.setStatus({ id: first.id, status: "on_site" }).orThrow();

      const done = await dispatch
        .setStatus({ id: first.id, status: "done", note: "Valve replaced" })
        .orThrow();

      expect(done.completionNote).toBe("Valve replaced");
      expect(done.completedAt).toBeInstanceOf(Temporal.Instant);

      const part = await dispatch
        .recordPart({
          workOrderId: first.id,
          input: { name: "Valve", quantity: "1.5", unit: "pc" },
        })
        .orThrow();

      expect(part.quantity).toBe("1.500");
      expect(await dispatch.parts(first.id).orThrow()).toHaveLength(1);
      expect(await dispatch.removePart(part.id).orThrow()).toBe(true);
      expect(await dispatch.create({ title: "Mine" }).then(hint)).toBe(
        "DISPATCH_FORBIDDEN",
      );
      expect(
        await dispatch
          .setStatus({ id: backlog.id, status: "cancelled" })
          .then(hint),
      ).toBe("DISPATCH_FORBIDDEN");

      await s.as(outsider);

      expect(await dispatch.get(first.id).orThrow()).toBeNull();

      await s.client.query("reset role");

      expect(
        (
          await s.rows<{ type: string }>(
            "select type from better_supabase.outbox_events where organization_id = $1 and type like 'work_order.%' order by position",
            [tenant],
          )
        ).map((row) => row.type),
      ).toEqual([
        "work_order.created",
        "work_order.created",
        "work_order.scheduled",
        "work_order.scheduled",
        "work_order.created",
        "work_order.status_changed",
        "work_order.status_changed",
        "work_order.status_changed",
        "work_order.part_used",
      ]);
    } finally {
      await s.close();
    }
  });

  it("takes a work order back to the backlog and off its route", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("dispatcher");
      const tech = await s.user("tech");
      await s.install(MODULES);
      const tenant = await s.organization(owner, { member: tech });

      const dispatch = createDispatch({
        transport: sqlTransport(s.sql),
        tenant,
      });

      await s.as(owner);

      const order = await dispatch
        .create({
          title: "Fix the lift",
          technicianId: tech.id,
          startsAt: at("2030-01-07T09:00:00Z"),
        })
        .orThrow();

      await dispatch
        .planRoute({
          technicianId: tech.id,
          day: DAY,
          workOrderIds: [order.id],
        })
        .orThrow();

      const back = await dispatch.unschedule(order.id).orThrow();

      expect(back.status).toBe("unscheduled");
      expect(back).not.toHaveProperty("technicianId");
      expect(
        (
          await dispatch
            .technicianDay({ day: DAY, technicianId: tech.id })
            .orThrow()
        ).stops,
      ).toEqual([]);
      expect(
        await dispatch.list({ status: "unscheduled" }).orThrow(),
      ).toHaveLength(1);
    } finally {
      await s.close();
    }
  });
});
