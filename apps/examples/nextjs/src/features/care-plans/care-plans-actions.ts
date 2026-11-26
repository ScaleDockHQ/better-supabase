"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

const Input = v.object({ planId: v.pipe(v.string(), v.uuid()) });

/** Publishes a draft plan and keeps the version it was published as. */
export const publishCarePlan = bsb.action(
  { input: Input, requireTenant: true, permission: "care_plans.publish" },
  async ({ planId }, { db, auth }) => {
    const plan = await db.carePlans.publish(planId);

    if (!plan.ok) {
      return plan;
    }

    await refreshCaller(auth, [tags.customers()]);

    return ok({ id: plan.data.id });
  },
);

/** Archives a plan; an archived plan leaves the client's dossier. */
export const archiveCarePlan = bsb.action(
  { input: Input, requireTenant: true, permission: "care_plans.write" },
  async ({ planId }, { db, auth }) => {
    const plan = await db.carePlans.archive(planId);

    if (!plan.ok) {
      return plan;
    }

    await refreshCaller(auth, [tags.customers()]);

    return ok({ id: plan.data.id });
  },
);
