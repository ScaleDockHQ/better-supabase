"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

const RECORD_TYPE = /^[a-z][a-z0-9_]*$/;

const Id = v.pipe(v.string(), v.minLength(1), v.maxLength(200));

/** Acknowledges the version of a record the member read. */
export const acknowledgeRecord = bsb.action(
  {
    input: v.object({
      type: v.pipe(v.string(), v.regex(RECORD_TYPE)),
      id: Id,
      versionId: v.pipe(v.string(), v.uuid()),
    }),
    requireTenant: true,
    permission: "acknowledgements.acknowledge",
  },
  async ({ type, id, versionId }, { db, auth }) => {
    const acknowledged = await db.acknowledgements.acknowledge({
      record: { type, id },
      versionId,
    });

    if (!acknowledged.ok) {
      return acknowledged;
    }

    await refreshCaller(auth);

    return ok({ id: acknowledged.data.id });
  },
);
