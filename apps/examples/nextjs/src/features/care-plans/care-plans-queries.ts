import "server-only";
import type {
  CarePlan,
  CarePlanActionKind,
  CarePlanActionStatus,
  CarePlanGoalStatus,
  CarePlanProblemStatus,
  CarePlanStatus,
} from "better-supabase/blocks/care-plans";

import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";

import { bsb } from "@/lib/supabase/server";

export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

/**
 * A failed read becomes `{ kind: "error" }` and is never cached, so Retry reads
 * again.
 */
async function settle<T>(load: () => Promise<T | null>): Promise<Loaded<T>> {
  try {
    const data = await load();

    return data === null ? { kind: "no-organization" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

/** An action as the editor shows it, serializable. */
export interface CarePlanActionRow {
  readonly id: string;
  readonly title: string;
  readonly kind: CarePlanActionKind;
  readonly status: CarePlanActionStatus;
  readonly requiresApproval: boolean;
  readonly teamRole: string | null;
}

export interface CarePlanGoalRow {
  readonly id: string;
  readonly title: string;
  readonly status: CarePlanGoalStatus;
  readonly targetOn: string | null;
  readonly actions: readonly CarePlanActionRow[];
}

export interface CarePlanProblemRow {
  readonly id: string;
  readonly title: string;
  readonly status: CarePlanProblemStatus;
  /** `system code`, such as `omaha 25`, or null without a code. */
  readonly code: string | null;
  readonly goals: readonly CarePlanGoalRow[];
}

/** One evaluation with its goal's title, serializable. */
export interface CarePlanEvaluationRow {
  readonly id: string;
  readonly goal: string;
  readonly status: CarePlanGoalStatus;
  readonly outcome: string | null;
  readonly evaluatedAt: string;
}

export interface CarePlanView {
  readonly clientName: string;
  readonly title: string;
  readonly status: CarePlanStatus;
  readonly version: number;
  readonly reviewOn: string | null;
  readonly problems: readonly CarePlanProblemRow[];
  readonly evaluations: readonly CarePlanEvaluationRow[];
}

/** No client, or a client without a plan yet. */
export type CarePlanState =
  | CarePlanView
  | { readonly clientName: string | null };

function viewOf(clientName: string, plan: CarePlan): CarePlanView {
  const goals = new Map<string, string>();

  const problems = plan.problems.map((problem) => ({
    id: problem.id,
    title: problem.title,
    status: problem.status,
    code:
      problem.code === undefined
        ? null
        : `${problem.codeSystem} ${problem.code}`,
    goals: problem.goals.map((goal) => {
      goals.set(goal.id, goal.title);

      return {
        id: goal.id,
        title: goal.title,
        status: goal.status,
        targetOn: goal.targetOn?.toString() ?? null,
        actions: goal.actions.map((action) => ({
          id: action.id,
          title: action.title,
          kind: action.kind,
          status: action.status,
          requiresApproval: action.requiresApproval,
          teamRole: action.teamRole ?? null,
        })),
      };
    }),
  }));

  return {
    clientName,
    title: plan.title,
    status: plan.status,
    version: plan.version,
    reviewOn: plan.reviewOn?.toString() ?? null,
    problems,
    evaluations: plan.evaluations.map((evaluation) => ({
      id: evaluation.id,
      goal: goals.get(evaluation.goalId) ?? "",
      status: evaluation.status,
      outcome: evaluation.outcome ?? null,
      evaluatedAt: evaluation.evaluatedAt.toString(),
    })),
  };
}

async function loadCarePlan(
  clientId: string | undefined,
): Promise<CarePlanState | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const clients = await db.customers
    .list({
      select: ["id", "name"],
      where: clientId === undefined ? {} : { id: clientId },
      orderBy: { name: "asc" },
      limit: 1,
    })
    .orThrow();

  const [client] = clients;

  if (client === undefined) {
    return { clientName: null };
  }

  const plans = await db.carePlans.list("customer", client.id).orThrow();

  const current = plans.find((plan) => plan.status === "active") ?? plans.at(0);

  if (current === undefined) {
    return { clientName: client.name };
  }

  return viewOf(client.name, await db.carePlans.get(current.id).orThrow());
}

/**
 * The client's care plan, or the first customer's without an id: the active
 * one, or the newest draft when none is active.
 */
export function getCarePlan(clientId?: string): Promise<Loaded<CarePlanState>> {
  return settle(() => loadCarePlan(clientId));
}
