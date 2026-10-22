import "server-only";
import type { ControlPosture } from "better-supabase/blocks/controls";
import type { MoneyJson } from "better-supabase/commerce";

import { moneyToJson } from "better-supabase/commerce";
import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";

import { blocks } from "@/lib/blocks";
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

/** An active contract as the renewals table shows it, serializable. */
export interface RenewalRow {
  readonly id: string;
  readonly title: string;
  readonly value: MoneyJson | null;
  readonly endsOn: string | null;
  readonly noticeDeadline: string | null;
  readonly autoRenew: boolean;
  /** Days from today to the notice deadline; negative once it passed. */
  readonly noticeInDays: number | null;
}

async function loadRenewals(): Promise<readonly RenewalRow[] | null> {
  "use cache: private";
  const { session, supabase } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const contracts = await blocks(supabase)
    .contracts.list(tenant, { status: "active", pageSize: 100 })
    .orThrow();

  const today = Date.parse(new Date().toISOString().slice(0, 10));

  return contracts
    .map((contract) => ({
      id: contract.id,
      title: contract.title,
      value: contract.value ? moneyToJson(contract.value) : null,
      endsOn: contract.endsOn?.toString() ?? null,
      noticeDeadline: contract.noticeDeadline?.toString() ?? null,
      autoRenew: contract.autoRenew,
      noticeInDays: contract.noticeDeadline
        ? Math.round(
            (Date.parse(contract.noticeDeadline.toString()) - today) /
              86_400_000,
          )
        : null,
    }))
    .toSorted((a, b) =>
      (a.noticeDeadline ?? "9999").localeCompare(b.noticeDeadline ?? "9999"),
    );
}

/** The organization's active contracts, the nearest notice deadline first. */
export function getRenewals(): Promise<Loaded<readonly RenewalRow[]>> {
  return settle(loadRenewals);
}

/** An overdue evidence task, serializable. */
export interface OverdueTaskRow {
  readonly id: string;
  readonly title: string;
  readonly controlCode: string | null;
  readonly dueOn: string;
}

export interface Posture {
  readonly frameworks: readonly ControlPosture[];
  readonly overdue: readonly OverdueTaskRow[];
}

async function loadPosture(): Promise<Posture | null> {
  "use cache: private";
  const { session, supabase } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const { controls } = blocks(supabase);

  const [frameworks, tasks] = await Promise.all([
    controls.posture(tenant).orThrow(),
    controls.evidenceTasks(tenant, { overdueOnly: true }).orThrow(),
  ]);

  return {
    frameworks,
    overdue: tasks.map((task) => ({
      id: task.id,
      title: task.title,
      controlCode: task.controlCode ?? null,
      dueOn: task.dueOn.toString(),
    })),
  };
}

/** The status rollup per framework and the overdue evidence tasks. */
export function getPosture(): Promise<Loaded<Posture>> {
  return settle(loadPosture);
}
