"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { given, Id, Name, Optional, plainDateOf } from "@/lib/form-input";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { LIMS_TAG } from "./lims-cache";

const TAGS = [LIMS_TAG];

/** Registers a sample, which gets the next SMP number. */
export const registerSample = bsb.action(
  {
    input: v.object({
      title: Name,
      kind: Optional,
      lot: Optional,
      receivedOn: Optional,
      notes: Optional,
    }),
    requireTenant: true,
    permission: "lims.write",
  },
  async (input, { db, auth }) => {
    const sample = await db.lims.registerSample({
      title: input.title,
      ...given("kind", input.kind),
      ...given("lot", input.lot),
      ...given("notes", input.notes),
      ...given("receivedOn", plainDateOf(input.receivedOn)),
    });

    if (!sample.ok) {
      return sample;
    }

    await refreshCaller(auth, TAGS);

    return ok({ id: sample.data.id });
  },
);

const Numeric = v.pipe(v.string(), v.trim(), v.regex(/^-?\d+(\.\d+)?$/u));

/** Saves a method with its specification limits. */
export const saveMethod = bsb.action(
  {
    input: v.object({
      key: v.pipe(v.string(), v.trim(), v.regex(/^[a-z0-9_]{1,60}$/u)),
      name: Name,
      unit: Optional,
      lowerLimit: Optional,
      upperLimit: Optional,
    }),
    requireTenant: true,
    permission: "lims.manage",
  },
  async (input, { db, auth }) => {
    const lower = input.lowerLimit;
    const upper = input.upperLimit;

    const saved = await db.lims.saveMethod({
      input: {
        key: input.key,
        name: input.name,
        ...given("unit", input.unit),
        ...given(
          "lowerLimit",
          lower !== undefined && v.is(Numeric, lower)
            ? Number(lower)
            : undefined,
        ),
        ...given(
          "upperLimit",
          upper !== undefined && v.is(Numeric, upper)
            ? Number(upper)
            : undefined,
        ),
      },
    });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth, TAGS);

    return ok({ id: saved.data.id });
  },
);

/**
 * Records one measurement. A value outside the method's limits is out of
 * specification and opens a nonconformity case.
 */
export const recordResult = bsb.action(
  {
    input: v.object({
      sampleId: Id,
      methodId: Id,
      instrumentId: Id,
      value: Numeric,
      note: Optional,
    }),
    requireTenant: true,
    permission: "lims.write",
  },
  async ({ sampleId, methodId, instrumentId, value, note }, { db, auth }) => {
    const saved = await db.lims.recordResult({
      sampleId,
      methodId,
      input: { value: Number(value), instrumentId, ...given("note", note) },
    });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth, TAGS);

    return ok({ outcome: saved.data.outcome });
  },
);

/** Completes a sample once its results are in. */
export const completeSample = bsb.action(
  {
    input: v.object({ sampleId: Id }),
    requireTenant: true,
    permission: "lims.write",
  },
  async ({ sampleId }, { db, auth }) => {
    const moved = await db.lims.completeSample(sampleId);

    if (!moved.ok) {
      return moved;
    }

    await refreshCaller(auth, TAGS);

    return ok(true);
  },
);

/** Releases a completed sample, or rejects one with a reason. */
export const decideSample = bsb.action(
  {
    input: v.object({
      sampleId: Id,
      action: v.picklist(["release", "reject"]),
      reason: Optional,
    }),
    requireTenant: true,
    permission: "lims.manage",
  },
  async ({ sampleId, action, reason }, { db, auth }) => {
    const moved =
      action === "release"
        ? await db.lims.releaseSample(sampleId)
        : await db.lims.rejectSample({
            sampleId,
            reason: reason ?? "Rejected",
          });

    if (!moved.ok) {
      return moved;
    }

    await refreshCaller(auth, TAGS);

    return ok(true);
  },
);
