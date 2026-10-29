import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  applyTemporal,
  blockCall,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  stringsOf,
  textOf,
} from "../shared.ts";

/** One level of a matrix. */
export interface RiskLevel {
  readonly value: number;
  readonly label: string;
}

/** One band of a matrix. */
export interface RiskBand {
  readonly key: string;
  readonly label: string;
  readonly min: number;
  readonly max: number;
}

/** A risk matrix. */
export interface RiskMatrix {
  readonly id: string;
  readonly organizationId: string;
  readonly key: string;
  readonly name: string;
  readonly likelihoodLevels: readonly RiskLevel[];
  readonly impactLevels: readonly RiskLevel[];
  readonly bands: readonly RiskBand[];
  readonly scoring: "product" | "sum";
  readonly isDefault: boolean;
}

/** A risk assessment. */
export interface RiskAssessment {
  readonly id: string;
  readonly inherentScore: number;
  readonly inherentBand: string;
  readonly residualScore: number;
  readonly residualBand: string;
  readonly rationale?: string;
  readonly assessedAt: Temporal.Instant;
}

/** A risk. */
export interface Risk {
  readonly id: string;
  readonly organizationId: string;
  readonly matrixId: string;
  readonly number: string;
  readonly title: string;
  readonly description?: string;
  readonly category?: string;
  readonly cause?: string;
  readonly consequence?: string;
  readonly ownerId?: string;
  readonly status:
    | "identified"
    | "assessed"
    | "treating"
    | "accepted"
    | "closed";
  readonly treatment?: "mitigate" | "accept" | "transfer" | "avoid";
  readonly reviewIntervalMonths?: number;
  readonly nextReviewOn?: Temporal.PlainDate;
  readonly inherentLikelihood?: number;
  readonly inherentImpact?: number;
  readonly inherentScore?: number;
  readonly inherentBand?: string;
  readonly residualLikelihood?: number;
  readonly residualImpact?: number;
  readonly residualScore?: number;
  readonly residualBand?: string;
  readonly currentAssessmentId?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  readonly assessments?: readonly RiskAssessment[];
}

/** The input of `create`. */
export interface RiskInput {
  readonly title: string;
  readonly description?: string;
  readonly category?: string;
  readonly cause?: string;
  readonly consequence?: string;
  readonly ownerId?: string;
  readonly matrixId?: string;
  readonly reviewIntervalMonths?: number;
}

/** The changes `update` accepts. */
export interface RiskChange {
  readonly title?: string;
  readonly description?: string;
  readonly category?: string;
  readonly cause?: string;
  readonly consequence?: string;
  readonly ownerId?: string;
  readonly reviewIntervalMonths?: number;
}

/** The input of `assess`. */
export interface RiskAssessmentInput {
  readonly inherentLikelihood: number;
  readonly inherentImpact: number;
  readonly residualLikelihood: number;
  readonly residualImpact: number;
  readonly rationale?: string;
}

/** One heatmap cell. */
export interface RiskHeatmapCell {
  readonly likelihood: number;
  readonly impact: number;
  readonly count: number;
  readonly riskIds: readonly string[];
}

/** A heatmap. */
export interface RiskHeatmap {
  readonly matrix: RiskMatrix;
  readonly cells: readonly RiskHeatmapCell[];
}

/** The filters `list` accepts. */
export interface RiskListOptions {
  readonly category?: string;
  readonly status?: Risk["status"];
  readonly ownerId?: string;
  readonly reviewDue?: boolean;
  readonly search?: string;
}

/** The risks client. */
export interface Risks {
  saveMatrix(
    organizationId: string,
    input: {
      readonly key: string;
      readonly name: string;
      readonly likelihoodLevels: readonly RiskLevel[];
      readonly impactLevels: readonly RiskLevel[];
      readonly bands: readonly RiskBand[];
      readonly scoring?: "product" | "sum";
      readonly isDefault?: boolean;
    },
  ): AsyncResult<RiskMatrix>;
  matrices(organizationId: string): AsyncResult<readonly RiskMatrix[]>;
  create(organizationId: string, input: RiskInput): AsyncResult<Risk>;
  update(riskId: string, changes: RiskChange): AsyncResult<Risk>;
  assess(riskId: string, input: RiskAssessmentInput): AsyncResult<Risk>;
  setTreatment(
    riskId: string,
    treatment: Risk["treatment"],
    note?: string,
  ): AsyncResult<Risk>;
  review(riskId: string, note?: string): AsyncResult<Risk>;
  close(riskId: string, reason: string): AsyncResult<Risk>;
  get(riskId: string): AsyncResult<Risk>;
  list(
    organizationId: string,
    options?: RiskListOptions,
  ): AsyncResult<readonly Risk[]>;
  heatmap(
    organizationId: string,
    options?: {
      readonly matrixId?: string;
      readonly basis?: "inherent" | "residual";
    },
  ): AsyncResult<RiskHeatmap>;
  notifyDueReviews(): AsyncResult<number>;
}

/** `createRisks` options. */
export interface RisksOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly hooks?: NoInfer<BlockHooks<Risks>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

const matrixOf = (value: unknown, fn: string): RiskMatrix => {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    likelihoodLevels: recordsOf(
      row["likelihoodLevels"],
      `${fn}.likelihoodLevels`,
    ).map((item) => ({
      value: Number(item["value"]),
      label: textOf(item["label"]),
    })),
    impactLevels: recordsOf(row["impactLevels"], `${fn}.impactLevels`).map(
      (item) => ({ value: Number(item["value"]), label: textOf(item["label"]) }),
    ),
    bands: recordsOf(row["bands"], `${fn}.bands`).map((item) => ({
      key: textOf(item["key"]),
      label: textOf(item["label"]),
      min: Number(item["min"]),
      max: Number(item["max"]),
    })),
    scoring: textOf(row["scoring"]) === "sum" ? "sum" : "product",
    isDefault: row["isDefault"] === true,
  };
};

const assessmentOf = (value: unknown, fn: string): RiskAssessment => {
  const row = recordOf(value, fn);
  const rationale = optionalText(row["rationale"]);

  return {
    id: textOf(row["id"]),
    inherentScore: Number(row["inherentScore"]),
    inherentBand: textOf(row["inherentBand"]),
    residualScore: Number(row["residualScore"]),
    residualBand: textOf(row["residualBand"]),
    ...(rationale === undefined ? {} : { rationale }),
    assessedAt: requiredInstant(row["assessedAt"], fn),
  };
};

const riskOf = (value: unknown, fn: string): Risk => {
  const row = recordOf(value, fn);
  const description = optionalText(row["description"]);
  const category = optionalText(row["category"]);
  const cause = optionalText(row["cause"]);
  const consequence = optionalText(row["consequence"]);
  const ownerId = optionalText(row["ownerId"]);
  const treatment = optionalText(row["treatment"]);
  const inherentBand = optionalText(row["inherentBand"]);
  const residualBand = optionalText(row["residualBand"]);
  const currentAssessmentId = optionalText(row["currentAssessmentId"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    matrixId: textOf(row["matrixId"]),
    number: textOf(row["number"]),
    title: textOf(row["title"]),
    ...(description === undefined ? {} : { description }),
    ...(category === undefined ? {} : { category }),
    ...(cause === undefined ? {} : { cause }),
    ...(consequence === undefined ? {} : { consequence }),
    ...(ownerId === undefined ? {} : { ownerId }),
    // SAFETY: risks.status has a check constraint on these five values.
    status: textOf(row["status"]) as Risk["status"],
    // SAFETY: risks.treatment has a check constraint on these four values.
    ...(treatment === undefined
      ? {}
      : { treatment: treatment as NonNullable<Risk["treatment"]> }),
    ...(row["reviewIntervalMonths"] === null ||
    row["reviewIntervalMonths"] === undefined
      ? {}
      : { reviewIntervalMonths: Number(row["reviewIntervalMonths"]) }),
    ...(row["nextReviewOn"] === null || row["nextReviewOn"] === undefined
      ? {}
      : { nextReviewOn: temporal().PlainDate.from(textOf(row["nextReviewOn"])) }),
    ...(row["inherentLikelihood"] === null ||
    row["inherentLikelihood"] === undefined
      ? {}
      : { inherentLikelihood: Number(row["inherentLikelihood"]) }),
    ...(row["inherentImpact"] === null || row["inherentImpact"] === undefined
      ? {}
      : { inherentImpact: Number(row["inherentImpact"]) }),
    ...(row["inherentScore"] === null || row["inherentScore"] === undefined
      ? {}
      : { inherentScore: Number(row["inherentScore"]) }),
    ...(inherentBand === undefined ? {} : { inherentBand }),
    ...(row["residualLikelihood"] === null ||
    row["residualLikelihood"] === undefined
      ? {}
      : { residualLikelihood: Number(row["residualLikelihood"]) }),
    ...(row["residualImpact"] === null || row["residualImpact"] === undefined
      ? {}
      : { residualImpact: Number(row["residualImpact"]) }),
    ...(row["residualScore"] === null || row["residualScore"] === undefined
      ? {}
      : { residualScore: Number(row["residualScore"]) }),
    ...(residualBand === undefined ? {} : { residualBand }),
    ...(currentAssessmentId === undefined ? {} : { currentAssessmentId }),
    createdAt: requiredInstant(row["createdAt"], fn),
    updatedAt: requiredInstant(row["updatedAt"], fn),
    ...(row["assessments"] === undefined
      ? {}
      : {
          assessments: recordsOf(row["assessments"], `${fn}.assessments`).map(
            (item) => assessmentOf(item, `${fn}.assessments`),
          ),
        }),
  };
};

const heatmapOf = (value: unknown, fn: string): RiskHeatmap => {
  const row = recordOf(value, fn);

  return {
    matrix: matrixOf(row["matrix"], `${fn}.matrix`),
    cells: recordsOf(row["cells"], `${fn}.cells`).map((item) => ({
      likelihood: Number(item["likelihood"]),
      impact: Number(item["impact"]),
      count: Number(item["count"]),
      riskIds: stringsOf(item["riskIds"]),
    })),
  };
};

/** The `risks` SQL module as typed calls. */
export function createRisks(options: RisksOptions): Risks {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  blockFields(undefined, "risk fields");

  const client: Risks = {
    saveMatrix: (organizationId, input) =>
      call(
        "save_risk_matrix",
        {
          tenant: organizationId,
          key: input.key,
          name: input.name,
          likelihood_levels: input.likelihoodLevels,
          impact_levels: input.impactLevels,
          bands: input.bands,
          scoring: input.scoring ?? "product",
          is_default: input.isDefault ?? false,
          matrix_id: null,
        },
        (value) => matrixOf(value, "save_risk_matrix"),
      ),
    matrices: (organizationId) =>
      call("list_risk_matrices", { tenant: organizationId }, (value) =>
        recordsOf(value, "list_risk_matrices").map((row) =>
          matrixOf(row, "list_risk_matrices"),
        ),
      ),
    create: (organizationId, input) =>
      call(
        "create_risk",
        { tenant: organizationId, input },
        (value) => riskOf(value, "create_risk"),
      ),
    update: (riskId, changes) =>
      call(
        "update_risk",
        { risk_id: riskId, changes },
        (value) => riskOf(value, "update_risk"),
      ),
    assess: (riskId, input) =>
      call(
        "assess_risk",
        {
          risk_id: riskId,
          inherent_likelihood: input.inherentLikelihood,
          inherent_impact: input.inherentImpact,
          residual_likelihood: input.residualLikelihood,
          residual_impact: input.residualImpact,
          rationale: input.rationale ?? null,
        },
        (value) => riskOf(value, "assess_risk"),
      ),
    setTreatment: (riskId, treatment, note) =>
      call(
        "set_risk_treatment",
        { risk_id: riskId, treatment, note: note ?? null },
        (value) => riskOf(value, "set_risk_treatment"),
      ),
    review: (riskId, note) =>
      call(
        "review_risk",
        { risk_id: riskId, note: note ?? null },
        (value) => riskOf(value, "review_risk"),
      ),
    close: (riskId, reason) =>
      call(
        "close_risk",
        { risk_id: riskId, reason },
        (value) => riskOf(value, "close_risk"),
      ),
    get: (riskId) =>
      call("get_risk", { risk_id: riskId }, (value) =>
        riskOf(value, "get_risk"),
      ),
    list: (organizationId, input) =>
      call(
        "list_risks",
        {
          tenant: organizationId,
          filters: {
            ...(input?.category === undefined
              ? {}
              : { category: input.category }),
            ...(input?.status === undefined ? {} : { status: input.status }),
            ...(input?.ownerId === undefined ? {} : { owner: input.ownerId }),
            ...(input?.reviewDue === undefined
              ? {}
              : { reviewDue: input.reviewDue }),
            ...(input?.search === undefined ? {} : { search: input.search }),
          },
        },
        (value) =>
          recordsOf(value, "list_risks").map((row) => riskOf(row, "list_risks")),
      ),
    heatmap: (organizationId, input) =>
      call(
        "risk_heatmap",
        {
          tenant: organizationId,
          matrix_id: input?.matrixId ?? null,
          basis: input?.basis ?? "residual",
        },
        (value) => heatmapOf(value, "risk_heatmap"),
      ),
    notifyDueReviews: () => call("notify_due_risk_reviews", {}, Number),
  };

  return withBlockHooks(client, options.hooks, {
    block: "risks",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
