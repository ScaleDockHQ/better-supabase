import "server-only";
import type { ControlPosture } from "better-supabase/blocks/compliance";
import type { LegalBasis } from "better-supabase/blocks/consents";
import type { MoneyJson } from "better-supabase/commerce";

import { moneyToJson } from "better-supabase/commerce";
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
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const contracts = await db.contracts
    .list({ organizationId: tenant, status: "active", pageSize: 100 })
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
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const { compliance: controls } = db;

  const [frameworks, tasks] = await Promise.all([
    controls.posture({ organizationId: tenant }).orThrow(),
    controls
      .evidenceTasks({ organizationId: tenant, overdueOnly: true })
      .orThrow(),
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

/** A consent purpose version as the register shows it, serializable. */
export interface PurposeRow {
  readonly id: string;
  readonly key: string;
  readonly title: string;
  readonly version: string;
  readonly legalBasis: LegalBasis;
  readonly requiresSignature: boolean;
  readonly validMonths: number | null;
  /** A system purpose every organization shares. */
  readonly system: boolean;
}

async function loadPurposes(): Promise<readonly PurposeRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const purposes = await db.consents.purposes().orThrow();

  return purposes.map((purpose) => ({
    id: purpose.id,
    key: purpose.key,
    title: purpose.title,
    version: purpose.version,
    legalBasis: purpose.legalBasis,
    requiresSignature: purpose.requiresSignature,
    validMonths: purpose.validMonths ?? null,
    system: purpose.organizationId === null,
  }));
}

/** The purposes the organization asks consent for, and the system ones. */
export function getPurposes(): Promise<Loaded<readonly PurposeRow[]>> {
  return settle(loadPurposes);
}
