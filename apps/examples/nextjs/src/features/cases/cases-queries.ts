import "server-only";
import type {
  CaseActionType,
  CaseBlocker,
  CaseStatus,
} from "better-supabase/blocks/cases";

import { tenantOf } from "better-supabase/next";

import { bsb } from "@/lib/supabase/server";

import type { OpenStage } from "./cases-stages";

import { isOpenStage } from "./cases-stages";

/** An open case as the board shows it, serializable. */
export interface CaseCard {
  readonly id: string;
  readonly number: string;
  readonly title: string;
  readonly kind: string;
  readonly severity: string | null;
  readonly stage: OpenStage;
  readonly pipelineId: string;
  readonly dueOn: string | null;
}

export interface CaseBoardData {
  readonly cards: readonly CaseCard[];
  /** Each pipeline's open stage ids by key, for a move to another column. */
  readonly stages: Readonly<
    Record<string, Readonly<Partial<Record<OpenStage, string>>>>
  >;
}

async function loadBoard(): Promise<CaseBoardData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const organizationId = tenantOf(session);

  if (!organizationId) {
    return null;
  }

  const [page, kinds, pipelines] = await Promise.all([
    db.cases.list({ status: "open", limit: 200 }).orThrow(),
    db.cases.kinds().orThrow(),
    db.pipelines.list({ organizationId, subjectType: "case" }).orThrow(),
  ]);

  const kindNames = new Map(kinds.map((kind) => [kind.id, kind.name]));

  const stageKeys = new Map(
    pipelines.flatMap((pipeline) =>
      pipeline.stages.map((stage) => [stage.id, stage.key] as const),
    ),
  );

  return {
    cards: page.items.flatMap((row): CaseCard[] => {
      const stage =
        row.stageId === undefined ? undefined : stageKeys.get(row.stageId);

      return stage !== undefined &&
        isOpenStage(stage) &&
        row.pipelineId !== undefined
        ? [
            {
              id: row.id,
              number: row.number,
              title: row.title,
              kind: kindNames.get(row.kindId) ?? "",
              severity: row.severity ?? null,
              stage,
              pipelineId: row.pipelineId,
              dueOn: row.dueOn?.toString() ?? null,
            },
          ]
        : [];
    }),
    stages: Object.fromEntries(
      pipelines.map((pipeline) => [
        pipeline.id,
        Object.fromEntries(
          pipeline.stages
            .filter((stage) => isOpenStage(stage.key))
            .map((stage) => [stage.key, stage.id]),
        ),
      ]),
    ),
  };
}

/** The organization's open cases, in a column for their stage. */
export function getCaseBoard(): Promise<CaseBoardData | null> {
  return loadBoard();
}

/** One action of a case, serializable. */
export interface CaseActionView {
  readonly id: string;
  readonly title: string;
  readonly type: CaseActionType;
  readonly required: boolean;
  readonly done: boolean;
}

/** The case the detail panel shows, serializable. */
export interface CaseDetailView {
  readonly id: string;
  readonly number: string;
  readonly title: string;
  readonly kind: string;
  readonly severity: string | null;
  readonly status: CaseStatus;
  readonly stage: string | null;
  readonly rootCause: string | null;
  readonly effectivenessDueOn: string | null;
  readonly ownerId: string | null;
  /** Whether the caller owns the case, which lets them close it. */
  readonly isOwner: boolean;
  readonly blockers: readonly CaseBlocker[];
  readonly actions: readonly CaseActionView[];
}

async function loadDetail(caseId: string): Promise<CaseDetailView | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const detail = await db.cases.get(caseId).orThrow();

  return {
    id: detail.id,
    number: detail.number,
    title: detail.title,
    kind: detail.kind.name,
    severity: detail.severity ?? null,
    status: detail.status,
    stage: detail.stage?.name ?? null,
    rootCause: detail.rootCause ?? null,
    effectivenessDueOn: detail.effectivenessDueOn?.toString() ?? null,
    ownerId: detail.ownerId ?? null,
    isOwner:
      session.kind === "user" && session.user.id === (detail.ownerId ?? ""),
    blockers: detail.blockers,
    actions: detail.actions.map((action) => ({
      id: action.id,
      title: action.title ?? "",
      type: action.type,
      required: action.required,
      done: action.done,
    })),
  };
}

/** A case with its blockers and actions. */
export function getCaseDetail(caseId: string): Promise<CaseDetailView | null> {
  return loadDetail(caseId);
}
