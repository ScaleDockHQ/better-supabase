"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/** Restores the whole batch of a trash item, whatever block trashed it. */
export const restoreTrashItem = bsb.action(
  {
    input: v.object({ id: Id }),
    requireOrganization: true,
    authorize: async () => can(await getPermissions(), "trash.restore"),
  },
  async ({ id }, { db, auth }) => {
    const restored = await db.trash.restore(id);

    if (!restored.ok) {
      return restored;
    }

    refreshCaller(auth);

    return ok({ count: restored.data.count });
  },
);

/** Deletes the batch's rows for good. */
export const purgeTrashItem = bsb.action(
  {
    input: v.object({ id: Id }),
    requireOrganization: true,
    authorize: async () => can(await getPermissions(), "trash.manage"),
  },
  async ({ id }, { db, auth }) => {
    const purged = await db.trash.purge(id);

    if (!purged.ok) {
      return purged;
    }

    refreshCaller(auth);

    return ok({ count: purged.data });
  },
);
