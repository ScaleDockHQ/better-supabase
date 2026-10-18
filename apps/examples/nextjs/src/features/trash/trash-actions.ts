"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { refreshCaller } from "@/lib/refresh-caller";
import { bs } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/** Restores the whole batch of a trash item, whatever block trashed it. */
export const restoreTrashItem = bs.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "trash.restore"),
  },
  async ({ id }, { supabase, auth }) => {
    const restored = await blocks(supabase).trash.restore(id);

    if (!restored.ok) {
      return restored;
    }

    refreshCaller(auth);

    return ok({ count: restored.data.count });
  },
);

/** Deletes the batch's rows for good. */
export const purgeTrashItem = bs.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "trash.manage"),
  },
  async ({ id }, { supabase, auth }) => {
    const purged = await blocks(supabase).trash.purge(id);

    if (!purged.ok) {
      return purged;
    }

    refreshCaller(auth);

    return ok({ count: purged.data });
  },
);
