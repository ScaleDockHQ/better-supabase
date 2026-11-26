"use server";

import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

const Input = v.object({ planId: v.pipe(v.string(), v.uuid()) });

/** Publishes a draft plan and keeps the version it was published as. */
export const publishCarePlan = bsb.blockAction(
  ({ db }) => db.carePlans,
  "publish",
  {
    input: Input,
    requireTenant: true,
    permission: "care_plans.publish",
    tags: () => [tags.customers()],
    refresh: true,
    args: ({ planId }) => [planId],
  },
  (plan) => ({ id: plan.id }),
);

/** Archives a plan; an archived plan leaves the client's dossier. */
export const archiveCarePlan = bsb.blockAction(
  ({ db }) => db.carePlans,
  "archive",
  {
    input: Input,
    requireTenant: true,
    permission: "care_plans.write",
    tags: () => [tags.customers()],
    refresh: true,
    args: ({ planId }) => [planId],
  },
  (plan) => ({ id: plan.id }),
);
