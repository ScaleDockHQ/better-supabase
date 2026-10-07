import "server-only";
import { blocks } from "@/lib/blocks";
import { workspaceSummary } from "@/lib/read-sets";
import { bs } from "@/lib/supabase/server";

/**
 * Four numbers, one GET: the read set runs as a single `stable` function.
 * `cacheTags` tags the entry with every table the set reads, so a new
 * customer or note revalidates it.
 */
export async function getWorkspaceSummary() {
  "use cache: private";
  const { db, session } = await bs.cached();
  bs.cacheTags(workspaceSummary);
  if (session.kind !== "user") return null;
  return db.$many(workspaceSummary, {}).orThrow();
}

export type OnboardingStepId = "customer" | "invite" | "api-key" | "plan";

export interface OnboardingStep {
  readonly id: OnboardingStepId;
  readonly href: string;
  readonly completed: boolean;
}

/** The getting-started checklist of an organization (the onboarding SQL module). */
export async function getOnboarding(organizationId: string) {
  "use cache: private";
  const { supabase } = await bs.cached();
  const progress = await blocks(supabase)
    .onboarding.progress(organizationId)
    .orThrow();
  return {
    completed: progress.completed,
    total: progress.total,
    done: progress.done,
    steps: progress.steps.map((step): OnboardingStep => ({
      id: step.id,
      href: step.href ?? "/",
      completed: step.completed,
    })),
  };
}

export interface UsageMeter {
  readonly meter: string;
  readonly used: number;
  readonly limit: number | null;
  readonly unlimited: boolean;
  /** ISO 8601; Temporal values don't cross into Client Components. */
  readonly resetsAt: string;
}

/** This period's usage against the plan's quotas (the usage SQL module). */
export async function getUsage(
  organizationId: string,
): Promise<readonly UsageMeter[]> {
  "use cache: private";
  const { supabase } = await bs.cached();
  const overview = await blocks(supabase)
    .usage.overview(organizationId)
    .orThrow();
  return overview.map((status) => ({
    meter: status.meter,
    used: status.used,
    limit: status.limit ?? null,
    unlimited: status.unlimited,
    resetsAt: status.resetsAt.toString(),
  }));
}
