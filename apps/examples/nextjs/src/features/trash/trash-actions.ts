"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/** Restores the whole batch of a trash item, whatever block trashed it. */
export const restoreTrashItem = bsb.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    permission: "trash.restore",
  },
  async ({ id }, { db, auth }) => {
    const restored = await db.trash.restore(id);

    if (!restored.ok) {
      return restored;
    }

    await refreshCaller(auth);

    return ok({ count: restored.data.count });
  },
);

/** Deletes the batch's rows for good. */
export const purgeTrashItem = bsb.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    permission: "trash.manage",
  },
  async ({ id }, { db, auth }) => {
    const purged = await db.trash.purge(id);

    if (!purged.ok) {
      return purged;
    }

    await refreshCaller(auth);

    return ok({ count: purged.data });
  },
);
