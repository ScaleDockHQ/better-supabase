"use server";

import type { WorkOrderInput } from "better-supabase/blocks/dispatch";
import type { ShipmentAddress } from "better-supabase/blocks/shipments";

import { ok } from "better-supabase";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

type Writable<T> = { -readonly [K in keyof T]: T[K] };

/** Where the example ships from; an app reads its warehouse from settings. */
const WAREHOUSE: ShipmentAddress = {
  company: "Acme Rockets",
  line1: "Keizersgracht 1",
  city: "Amsterdam",
  postalCode: "1015 CJ",
  country: "NL",
};

const Text = (max: number) =>
  v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(max));

const Optional = (max: number) =>
  v.optional(
    v.pipe(
      v.string(),
      v.trim(),
      v.maxLength(max),
      v.transform((value) => (value === "" ? undefined : value)),
    ),
  );

/** Opens a work order in the backlog, for the board to schedule. */
export const createWorkOrder = bsb.action(
  {
    input: v.object({
      title: Text(200),
      address: Optional(500),
      priority: v.optional(
        v.picklist(["low", "normal", "high", "urgent"]),
        "normal",
      ),
    }),
    requireOrganization: true,
    authorize: (session) => can(session, "dispatch.manage"),
  },
  async ({ title, address, priority }, { db, auth }) => {
    const order: Writable<WorkOrderInput> = { title, priority };

    if (address !== undefined) {
      order.address = address;
    }

    const created = await db.dispatch.create(order);

    if (!created.ok) {
      return created;
    }

    refreshCaller(auth);

    return ok({ id: created.data.id });
  },
);

/** Moves one of the caller's work orders on: en route, on site, then done. */
export const advanceWorkOrder = bsb.action(
  {
    input: v.object({
      id: v.pipe(v.string(), v.uuid()),
      to: v.picklist(["en_route", "on_site", "done"]),
    }),
    requireOrganization: true,
    authorize: (session) => can(session, "dispatch.work"),
  },
  async ({ id, to }, { db, auth }) => {
    const moved = await db.dispatch.setStatus(id, to);

    if (!moved.ok) {
      return moved;
    }

    refreshCaller(auth);

    return ok({ status: moved.data.status });
  },
);

/** Creates a draft shipment of one package from the warehouse. */
export const createShipment = bsb.action(
  {
    input: v.object({
      name: Text(200),
      line1: Text(200),
      city: Text(100),
      postalCode: Optional(20),
      country: v.pipe(
        v.string(),
        v.trim(),
        v.toUpperCase(),
        v.regex(/^[A-Z]{2}$/u),
      ),
      weightGrams: v.pipe(
        v.string(),
        v.transform(Number),
        v.integer(),
        v.minValue(1),
        v.maxValue(70_000),
      ),
    }),
    requireOrganization: true,
    authorize: (session) => can(session, "shipments.manage"),
  },
  async (
    { name, line1, city, postalCode, country, weightGrams },
    { db, auth },
  ) => {
    const to: Writable<ShipmentAddress> = { name, line1, city, country };

    if (postalCode !== undefined) {
      to.postalCode = postalCode;
    }

    const created = await db.shipments.create({
      from: WAREHOUSE,
      to,
      packages: [{ weightGrams }],
    });

    if (!created.ok) {
      return created;
    }

    refreshCaller(auth);

    return ok({ id: created.data.id });
  },
);
