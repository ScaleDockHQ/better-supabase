"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/** Restores the whole batch of a trash item, whatever block trashed it. */
export const restoreTrashItem = bsb.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    permission: "trash.restore",
    evictSession: true,
  },
  async ({ id }, { db }) => {
    const restored = await db.trash.restore(id);

    if (!restored.ok) {
      return restored;
    }

    return ok({ count: restored.data.count });
  },
);

/** Deletes the batch's rows for good. */
export const purgeTrashItem = bsb.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    permission: "trash.manage",
    evictSession: true,
  },
  async ({ id }, { db }) => {
    const purged = await db.trash.purge(id);

    if (!purged.ok) {
      return purged;
    }

    return ok({ count: purged.data });
  },
);
