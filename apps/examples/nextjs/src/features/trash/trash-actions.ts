"use server";

import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/** Restores the whole batch of a trash item, whatever block trashed it. */
export const restoreTrashItem = bsb.blockAction(
  ({ db }) => db.trash,
  "restore",
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    permission: "trash.restore",
    evictSession: true,
    args: ({ id }) => [id],
  },
  (restored) => ({ count: restored.count }),
);

/** Deletes the batch's rows for good. */
export const purgeTrashItem = bsb.blockAction(
  ({ db }) => db.trash,
  "purge",
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    permission: "trash.manage",
    evictSession: true,
    args: ({ id }) => [id],
  },
  (purged) => ({ count: purged }),
);
