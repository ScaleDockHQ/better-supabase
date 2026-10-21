import type { Result } from "better-supabase";

import { dbError, err, fromProblem, isProblem, ok } from "better-supabase";
import * as v from "valibot";

import { bs, supabase } from "./supabase/client.native";

const CheckoutStarted = v.object({ url: v.optional(v.string()) });

export interface PlanOption {
  readonly key: string;
  readonly name: string;
  readonly priceCents: number;
}

/**
 * The fixture's plan catalog (`public.plans`, readable by every signed-in user)
 * and the organization's plan, through PostgREST as the caller.
 */
export async function loadPlanCatalog(
  organizationId: string,
): Promise<{
  readonly plans: readonly PlanOption[];
  readonly current: string | undefined;
}> {
  const [plans, subscription] = await Promise.all([
    bs.db.plans
      .findMany({
        select: ["key", "name", "price_cents"],
        orderBy: { position: "asc" },
      })
      .orThrow(),
    bs.db.subscriptions
      .findFirst({
        select: ["plan_key"],
        where: { organization_id: organizationId },
      })
      .orThrow(),
  ]);

  return {
    plans: plans.map((plan) => ({
      key: plan.key,
      name: plan.name,
      priceCents: plan.price_cents,
    })),
    current: subscription?.plan_key ?? undefined,
  };
}

/**
 * Starts Checkout through the app's own API route (`app/api/checkout+api.ts`),
 * which holds the Stripe key, with the caller's access token. In development
 * Expo resolves the relative URL against the dev server.
 */
export async function startCheckout(
  plan: string,
): Promise<Result<{ readonly url: string | undefined }>> {
  const { data } = await supabase.auth.getSession();

  const response = await fetch("/api/checkout", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${data.session?.access_token ?? ""}`,
    },
    body: JSON.stringify({ plan }),
  });

  const body: unknown = await response.json();

  if (isProblem(body)) {
    return err(fromProblem(body));
  }

  const started = v.safeParse(CheckoutStarted, body);

  if (!response.ok || !started.success) {
    return err(dbError("unexpected", `Checkout answered ${response.status}`));
  }

  return ok({ url: started.output.url });
}
