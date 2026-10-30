import "server-only";
import type {
  InspectionMemberRole,
  InspectionStatus,
} from "better-supabase/blocks/inspections";

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

/** An inspection as the programme calendar shows it, serializable. */
export interface InspectionRow {
  readonly id: string;
  readonly number: string;
  readonly title: string;
  readonly kind: string;
  readonly status: InspectionStatus;
  readonly program: string | null;
  readonly plannedStart: string | null;
}

async function loadCalendar(): Promise<readonly InspectionRow[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const [inspections, programs] = await Promise.all([
    db.inspections.list({ limit: 200 }).orThrow(),
    db.inspections.programs().orThrow(),
  ]);

  const programNames = new Map(programs.map((row) => [row.id, row.name]));

  return inspections
    .map((row) => ({
      id: row.id,
      number: row.number,
      title: row.title,
      kind: row.kind,
      status: row.status,
      program:
        row.programId === undefined
          ? null
          : (programNames.get(row.programId) ?? null),
      plannedStart: row.plannedStart?.toString() ?? null,
    }))
    .toSorted((a, b) =>
      (a.plannedStart ?? "9999").localeCompare(b.plannedStart ?? "9999"),
    );
}

/** The organization's inspections, the earliest planned first. */
export function getInspectionCalendar(): Promise<
  Loaded<readonly InspectionRow[]>
> {
  return settle(loadCalendar);
}

/** One finding of an inspection, serializable. */
export interface FindingView {
  readonly id: string;
  readonly number: number;
  readonly type: string;
  readonly title: string;
  readonly clause: string | null;
  readonly needsCase: boolean;
  readonly caseId: string | null;
}

/** The inspection the run panel shows, serializable. */
export interface InspectionRunView {
  readonly id: string;
  readonly number: string;
  readonly title: string;
  readonly kind: string;
  readonly status: InspectionStatus;
  readonly checklist: string | null;
  readonly team: readonly {
    readonly userId: string;
    readonly role: InspectionMemberRole;
  }[];
  readonly findings: readonly FindingView[];
}

async function loadRun(
  inspectionId: string,
): Promise<InspectionRunView | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const detail = await db.inspections.get(inspectionId).orThrow();

  return {
    id: detail.id,
    number: detail.number,
    title: detail.title,
    kind: detail.kind,
    status: detail.status,
    checklist: detail.checklist?.status ?? null,
    team: detail.members.map((member) => ({
      userId: member.userId,
      role: member.role,
    })),
    findings: detail.findings.map((finding) => ({
      id: finding.id,
      number: finding.number,
      type: finding.type,
      title: finding.title,
      clause: finding.clause ?? null,
      needsCase: finding.needsCase,
      caseId: finding.caseId ?? null,
    })),
  };
}

/** An inspection with its team, checklist and findings. */
export function getInspectionRun(
  inspectionId: string,
): Promise<Loaded<InspectionRunView>> {
  return settle(() => loadRun(inspectionId));
}
