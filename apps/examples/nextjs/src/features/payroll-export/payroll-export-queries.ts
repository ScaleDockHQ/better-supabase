import "server-only";
import type { PayrollRunStatus } from "better-supabase/blocks/payroll-export";

import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";

import { bsb } from "@/lib/supabase/server";

export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

/** A payroll run as the list shows it, serializable. */
export interface PayrollRunRow {
  readonly id: string;
  readonly label: string | null;
  readonly periodFrom: string;
  readonly periodTo: string;
  readonly status: PayrollRunStatus;
  readonly format: string | null;
  readonly lineCount: number;
}

async function loadRuns(): Promise<readonly PayrollRunRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const runs = await db.payrollExport.list().orThrow();

  return runs.map((run): PayrollRunRow => ({
    id: run.id,
    label: run.label ?? null,
    periodFrom: run.periodFrom.toString(),
    periodTo: run.periodTo.toString(),
    status: run.status,
    format: run.format ?? null,
    lineCount: run.lineCount,
  }));
}

/**
 * A failed read becomes `{ kind: "error" }` and is never cached, so Retry reads
 * again.
 */
export async function getPayrollRuns(): Promise<
  Loaded<readonly PayrollRunRow[]>
> {
  try {
    const data = await loadRuns();

    return data === null ? { kind: "no-organization" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}
