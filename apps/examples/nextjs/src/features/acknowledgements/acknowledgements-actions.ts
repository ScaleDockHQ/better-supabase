"use server";

import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

const RECORD_TYPE = /^[a-z][a-z0-9_]*$/;

const Id = v.pipe(v.string(), v.minLength(1), v.maxLength(200));

/** Acknowledges the version of a record the member read. */
export const acknowledgeRecord = bsb.blockAction(
  ({ db }) => db.acknowledgements,
  "acknowledge",
  {
    input: v.object({
      type: v.pipe(v.string(), v.regex(RECORD_TYPE)),
      id: Id,
      versionId: v.pipe(v.string(), v.uuid()),
    }),
    requireTenant: true,
    permission: "acknowledgements.acknowledge",
    tags: () => [tags.acknowledgements()],
    refresh: true,
    args: ({ type, id, versionId }) => [{ record: { type, id }, versionId }],
  },
  (acknowledged) => ({ id: acknowledged.id }),
);
