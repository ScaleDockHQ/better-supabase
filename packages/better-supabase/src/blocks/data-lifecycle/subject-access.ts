import type { BlockEntities, EntityErase } from "../entity-surface.ts";
import type {
  DataLifecycle,
  DataSubjectRequest,
  DataSubjectRequestKind,
} from "./data-lifecycle.ts";

import { AsyncResult, ok, type Result } from "../../core/result.ts";

/** What `subjectAccessPlan` reads of a block: its name and declared entities. */
export interface SubjectAccessBlock {
  readonly name: string;
  readonly entities?: BlockEntities | undefined;
}

/** One entity that holds a person's rows. */
export interface SubjectAccessStep {
  readonly block: string;
  readonly entity: string;
  /** The column that names the person. */
  readonly subjectColumn: string;
  /** The columns an access request returns and an erasure blanks or removes. */
  readonly columns: readonly string[];
  /** What an erasure does to the rows (`delete` when the entity declares none). */
  readonly erase: EntityErase;
  /** The retention class the rows follow, when declared. */
  readonly retention: string | undefined;
  /** `true` when a legal hold on the retention class stops the erasure. */
  readonly legalHold: boolean;
}

/** An entity with personal data that the plan cannot reach, and why. */
export interface SubjectAccessGap {
  readonly block: string;
  readonly entity: string;
  readonly reason: "no-subject-column" | "append-only-delete";
}

export interface SubjectAccessPlan {
  /** Every entity an access or portability request collects, by block. */
  readonly access: readonly SubjectAccessStep[];
  /** The steps an erasure runs, grouped by what it does to the rows. */
  readonly erasure: {
    readonly delete: readonly SubjectAccessStep[];
    readonly anonymize: readonly SubjectAccessStep[];
    readonly keep: readonly SubjectAccessStep[];
  };
  /** Entities that declare `personalData` but cannot be collected or erased. */
  readonly gaps: readonly SubjectAccessGap[];
}

export interface SubjectAccessPlanOptions {
  /** Plan only these blocks; default every block passed in. */
  readonly blocks?: readonly string[];
}

/**
 * Reads the `personalData` declarations of the manifests and returns the
 * entities an access or erasure request covers (ADR 0899). An erasure never
 * deletes the rows of an append-only entity: those must declare `anonymize` or
 * `keep`, and one that does not lands in `gaps` so the audit trail stays
 * intact.
 */
export function subjectAccessPlan(
  blocks: readonly SubjectAccessBlock[],
  options: SubjectAccessPlanOptions = {},
): SubjectAccessPlan {
  const access: SubjectAccessStep[] = [];
  const gaps: SubjectAccessGap[] = [];

  for (const block of blocks) {
    if (options.blocks && !options.blocks.includes(block.name)) {
      continue;
    }

    for (const [entity, surface] of Object.entries(block.entities ?? {})) {
      const columns = surface.personalData ?? [];

      if (columns.length === 0) {
        continue;
      }

      if (surface.subjectColumn === undefined) {
        gaps.push({ block: block.name, entity, reason: "no-subject-column" });
        continue;
      }

      const erase = surface.erase ?? "delete";

      if (erase === "delete" && surface.mutability === "append-only") {
        gaps.push({ block: block.name, entity, reason: "append-only-delete" });
        continue;
      }

      access.push({
        block: block.name,
        entity,
        subjectColumn: surface.subjectColumn,
        columns,
        erase,
        retention: surface.retention,
        legalHold: surface.legalHold ?? false,
      });
    }
  }

  const only = (erase: EntityErase): readonly SubjectAccessStep[] =>
    access.filter((step) => step.erase === erase);

  return {
    access,
    erasure: {
      delete: only("delete"),
      anonymize: only("anonymize"),
      keep: only("keep"),
    },
    gaps,
  };
}

export interface SubjectAccessRequestInput {
  readonly organizationId: string;
  readonly kind: DataSubjectRequestKind;
  readonly requester: string;
  readonly subject: { readonly type: string; readonly id: string };
  /** The manifests to plan over, such as `BLOCK_MANIFESTS`. */
  readonly blocks: readonly SubjectAccessBlock[];
  readonly details?: string;
  readonly plan?: SubjectAccessPlanOptions;
}

export interface SubjectAccessRequestResult {
  readonly request: DataSubjectRequest;
  readonly plan: SubjectAccessPlan;
}

/**
 * Opens a data subject request and returns it with the plan the manifests
 * declare, so one call tells the app which entities to collect or erase. The
 * request's `details` lists the planned entities for the reviewer. Fulfilling
 * it stays `fulfilDataSubjectRequest`, which refuses an erasure under a legal
 * hold.
 */
export function subjectAccessRequest(
  lifecycle: Pick<DataLifecycle, "openDataSubjectRequest">,
  input: SubjectAccessRequestInput,
): AsyncResult<SubjectAccessRequestResult> {
  return AsyncResult.from(() => openRequest(lifecycle, input));
}

async function openRequest(
  lifecycle: Pick<DataLifecycle, "openDataSubjectRequest">,
  input: SubjectAccessRequestInput,
): Promise<Result<SubjectAccessRequestResult>> {
  const plan = subjectAccessPlan(input.blocks, input.plan);

  const listed = plan.access
    .map((step) => `${step.block}.${step.entity}`)
    .join(", ");

  const details = [input.details, listed === "" ? undefined : `Covers: ${listed}`]
    .filter((part): part is string => part !== undefined)
    .join("\n");

  const opened = await lifecycle.openDataSubjectRequest({
    organizationId: input.organizationId,
    kind: input.kind,
    requester: input.requester,
    subject: input.subject,
    ...(details === "" ? {} : { details }),
  });

  return opened.ok ? ok({ request: opened.data, plan }) : opened;
}
