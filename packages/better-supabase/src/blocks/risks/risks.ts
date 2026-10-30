import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type {
  RiskMatrixBand,
  RiskMatrixLevel,
} from "../../sql/modules/risks-sql.ts";
import type { BlockOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export type { RiskMatrixBand, RiskMatrixLevel };

const STATUSES = [
  "identified",
  "assessed",
  "treating",
  "accepted",
  "closed",
] as const;

const TREATMENTS = ["mitigate", "accept", "transfer", "avoid"] as const;

const SCORINGS = ["product", "sum"] as const;

/** Where a risk stands. */
export type RiskStatus = (typeof STATUSES)[number];

/**
 * How a risk is treated: `mitigate` and `transfer` make it treating, `accept`
 * accepts it and `avoid` closes it.
 */
export type RiskTreatment = (typeof TREATMENTS)[number];

/** How a matrix turns a likelihood and an impact into a score. */
export type RiskScoring = (typeof SCORINGS)[number];

/** A likelihood and an impact, with the score and band they give. */
export interface RiskRating {
  readonly likelihood: number;
  readonly impact: number;
  readonly score: number;
  /** The key of the band the score falls in, such as `high`. */
  readonly band: string;
}

export interface RiskMatrix {
  readonly id: string;
  readonly organizationId: string;
  readonly key: string;
  readonly name: string;
  readonly likelihoodLevels: readonly RiskMatrixLevel[];
  readonly impactLevels: readonly RiskMatrixLevel[];
  readonly bands: readonly RiskMatrixBand[];
  readonly scoring: RiskScoring;
  readonly isDefault: boolean;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface RiskMatrixInput {
  /** Lowercase letters, digits, dashes and underscores, unique per organization. */
  readonly key: string;
  readonly name: string;
  /** Values 1 to n, 2 to 10 levels. */
  readonly likelihoodLevels: readonly RiskMatrixLevel[];
  readonly impactLevels: readonly RiskMatrixLevel[];
  /** Cover every score from the lowest to the highest, without gaps. */
  readonly bands: readonly RiskMatrixBand[];
  /** Default `product`. */
  readonly scoring?: RiskScoring;
  /** Make it the organization's default matrix. */
  readonly isDefault?: boolean;
  /** Changes this matrix instead of creating one. */
  readonly matrixId?: string;
}

/** A risk. `F` types the extra columns the `fields` schema describes. */
export interface Risk<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  /** Such as `RSK-0001`. */
  readonly number: string;
  readonly matrixId: string;
  readonly title: string;
  readonly description?: string;
  readonly category: string;
  readonly cause?: string;
  readonly consequence?: string;
  readonly ownerId?: string;
  readonly status: RiskStatus;
  readonly treatment?: RiskTreatment;
  /**
   * An assessment or a review moves the next review this far ahead; 12 when
   * unset.
   */
  readonly reviewIntervalMonths?: number;
  readonly nextReviewOn?: Temporal.PlainDate;
  readonly reviewedAt?: Temporal.Instant;
  /** Before controls; absent until the first assessment. */
  readonly inherent?: RiskRating;
  /** After controls; absent until the first assessment. */
  readonly residual?: RiskRating;
  readonly currentAssessmentId?: string;
  readonly closedAt?: Temporal.Instant;
  readonly archivedAt?: Temporal.Instant;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  readonly fields: ExtraFields<F>;
}

export interface RiskAssessment {
  readonly id: string;
  readonly riskId: string;
  readonly inherent: RiskRating;
  readonly residual: RiskRating;
  readonly rationale?: string;
  /** The frozen version of the risk the assessment recorded. */
  readonly versionId?: string;
  readonly assessedBy?: string;
  readonly assessedAt: Temporal.Instant;
}

/** A record linked to a risk, with its title. */
export interface RiskLink {
  readonly linkId: string;
  readonly type: string;
  readonly id: string;
  readonly title?: string;
}

/** A risk with its matrix, assessments, barriers and cases. */
export interface RiskDetail<
  F extends object = Record<never, never>,
> extends Risk<F> {
  readonly matrix: RiskMatrix;
  /** Newest first. */
  readonly assessments: readonly RiskAssessment[];
  /** The records the risk is `mitigated_by`: controls, work items, files. */
  readonly barriers: readonly RiskLink[];
  /** The cases the risk `materialized_as`. */
  readonly cases: readonly RiskLink[];
}

export interface RiskInput<F extends object = Record<never, never>> {
  readonly title: string;
  /** One of `options.categories`. */
  readonly category: string;
  readonly description?: string | null;
  readonly cause?: string | null;
  readonly consequence?: string | null;
  readonly ownerId?: string | null;
  /** Default the organization's default matrix. */
  readonly matrixId?: string;
  /** 1 to 120. */
  readonly reviewIntervalMonths?: number | null;
  /** The extra columns, keyed by database name. */
  readonly fields?: Partial<F>;
}

/** What `update` changes; keys left out keep their value. */
export type RiskChange<F extends object = Record<never, never>> = Partial<
  Omit<RiskInput<F>, "title" | "category">
> & { readonly title?: string; readonly category?: string };

/** A likelihood and an impact, before and after controls. */
export interface RiskAssessmentInput {
  readonly inherent: { readonly likelihood: number; readonly impact: number };
  readonly residual: { readonly likelihood: number; readonly impact: number };
  readonly rationale?: string;
}

export interface RiskListOptions {
  readonly category?: string;
  /** The residual band, such as `high`. */
  readonly band?: string;
  readonly ownerId?: string;
  /** Closed risks are left out unless this asks for them. */
  readonly status?: RiskStatus;
  /** Only risks whose review date has come. */
  readonly reviewDue?: boolean;
  /** Matches the title, number, description, cause or consequence. */
  readonly search?: string;
  /** 1 to 200. Default 50. */
  readonly limit?: number;
  readonly offset?: number;
}

/** One cell of a heatmap: the open risks rated at a likelihood and impact. */
export interface RiskHeatmapCell {
  readonly likelihood: number;
  readonly impact: number;
  readonly score: number;
  readonly band: string;
  readonly count: number;
  readonly riskIds: readonly string[];
}

export interface RiskHeatmap {
  readonly matrix: RiskMatrix;
  readonly basis: "residual" | "inherent";
  /** One per likelihood and impact, by likelihood then impact. */
  readonly cells: readonly RiskHeatmapCell[];
}

export interface Risks<F extends object = Record<never, never>> {
  /** Creates or changes a matrix; needs `risks.manage`. */
  saveMatrix(input: RiskMatrixInput): AsyncResult<RiskMatrix>;
  /** The organization's matrices, the default first. */
  matrices(): AsyncResult<readonly RiskMatrix[]>;
  /** Registers an identified risk; needs `risks.write`. */
  create(input: RiskInput<F>): AsyncResult<Risk<F>>;
  /** Changes a risk; its matrix only before the first assessment. */
  update(riskId: string, change: RiskChange<F>): AsyncResult<Risk<F>>;
  /** Scores a risk before and after controls; needs `risks.assess`. */
  assess(riskId: string, input: RiskAssessmentInput): AsyncResult<Risk<F>>;
  /** Sets the treatment; accepting needs `risks.manage`. */
  setTreatment(
    riskId: string,
    treatment: RiskTreatment,
    note?: string,
  ): AsyncResult<Risk<F>>;
  /** Records a review and moves the next one ahead; needs `risks.assess`. */
  review(riskId: string, note?: string): AsyncResult<Risk<F>>;
  /** Closes a risk with a reason; needs `risks.manage`. */
  close(riskId: string, reason: string): AsyncResult<Risk<F>>;
  get(riskId: string): AsyncResult<RiskDetail<F>>;
  list(options?: RiskListOptions): AsyncResult<readonly Risk<F>[]>;
  /**
   * The open risks per matrix cell; the default matrix and residual rating by
   * default.
   */
  heatmap(options?: {
    readonly matrixId?: string;
    readonly basis?: "residual" | "inherent";
  }): AsyncResult<RiskHeatmap>;
  /** Reports the risks whose review is due; service role only. */
  notifyDueReviews(): AsyncResult<number>;
}

export interface RisksOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /**
   * A Standard Schema for the risk's extra columns
   * (`blocks.risks.options.extraColumns`), keyed by database name. It types and
   * parses them on reads, and validates them on writes.
   */
  readonly fields?: S;
  readonly hooks?: NoInfer<BlockHooks<Risks<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

const numberOf = (value: unknown): number =>
  typeof value === "number" ? value : Number(value ?? 0);

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

const optionalDate = (value: unknown): Temporal.PlainDate | undefined =>
  typeof value === "string" && value !== ""
    ? temporal().PlainDate.from(value)
    : undefined;

const optionalNumber = (value: unknown): number | undefined =>
  value === null || value === undefined ? undefined : numberOf(value);

function ratingOf(value: unknown): RiskRating | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  return {
    likelihood: numberOf(value["likelihood"]),
    impact: numberOf(value["impact"]),
    score: numberOf(value["score"]),
    band: textOf(value["band"]),
  };
}

function levelsOf(value: unknown): readonly RiskMatrixLevel[] {
  return Array.isArray(value)
    ? value
        .filter(isRecord)
        .map((level) => ({
          value: numberOf(level["value"]),
          label: textOf(level["label"]),
        }))
    : [];
}

function matrixOf(value: unknown, fn: string): RiskMatrix {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    key: textOf(row["key"]),
    name: textOf(row["name"]),
    likelihoodLevels: levelsOf(row["likelihoodLevels"]),
    impactLevels: levelsOf(row["impactLevels"]),
    bands: Array.isArray(row["bands"])
      ? row["bands"]
          .filter(isRecord)
          .map((band) => ({
            key: textOf(band["key"]),
            label: textOf(band["label"]),
            min: numberOf(band["min"]),
            max: numberOf(band["max"]),
          }))
      : [],
    scoring: enumOrThrow(row["scoring"], SCORINGS, "risk matrix scoring"),
    isDefault: row["isDefault"] === true,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
  };
}

function riskOf(value: unknown, fn: string): Risk {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    number: textOf(row["number"]),
    matrixId: textOf(row["matrixId"]),
    title: textOf(row["title"]),
    category: textOf(row["category"]),
    status: enumOrThrow(row["status"], STATUSES, "risk status"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
    ...optional("description", optionalText(row["description"])),
    ...optional("cause", optionalText(row["cause"])),
    ...optional("consequence", optionalText(row["consequence"])),
    ...optional("ownerId", optionalText(row["ownerId"])),
    ...optional(
      "treatment",
      row["treatment"] === null || row["treatment"] === undefined
        ? undefined
        : enumOrThrow(row["treatment"], TREATMENTS, "risk treatment"),
    ),
    ...optional(
      "reviewIntervalMonths",
      optionalNumber(row["reviewIntervalMonths"]),
    ),
    ...optional("nextReviewOn", optionalDate(row["nextReviewOn"])),
    ...optional("reviewedAt", optionalInstant(row["reviewedAt"])),
    ...optional("inherent", ratingOf(row["inherent"])),
    ...optional("residual", ratingOf(row["residual"])),
    ...optional(
      "currentAssessmentId",
      optionalText(row["currentAssessmentId"]),
    ),
    ...optional("closedAt", optionalInstant(row["closedAt"])),
    ...optional("archivedAt", optionalInstant(row["archivedAt"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
  };
}

function assessmentOf(row: Readonly<Record<string, unknown>>): RiskAssessment {
  const rating = (key: string): RiskRating =>
    ratingOf(row[key]) ?? { likelihood: 0, impact: 0, score: 0, band: "" };

  return {
    id: textOf(row["id"]),
    riskId: textOf(row["riskId"]),
    inherent: rating("inherent"),
    residual: rating("residual"),
    assessedAt: requiredInstant(row["assessedAt"], "assessedAt"),
    ...optional("rationale", optionalText(row["rationale"])),
    ...optional("versionId", optionalText(row["versionId"])),
    ...optional("assessedBy", optionalText(row["assessedBy"])),
  };
}

function linksOf(value: unknown): readonly RiskLink[] {
  return Array.isArray(value)
    ? value
        .filter(isRecord)
        .map((link) => ({
          linkId: textOf(link["linkId"]),
          type: textOf(link["type"]),
          id: textOf(link["id"]),
          ...optional("title", optionalText(link["title"])),
        }))
    : [];
}

function detailOf(value: unknown, fn: string): RiskDetail {
  const row = recordOf(value, fn);

  return {
    ...riskOf(row, fn),
    matrix: matrixOf(row["matrix"], fn),
    assessments: Array.isArray(row["assessments"])
      ? row["assessments"].filter(isRecord).map(assessmentOf)
      : [],
    barriers: linksOf(row["barriers"]),
    cases: linksOf(row["cases"]),
  };
}

function heatmapOf(value: unknown, fn: string): RiskHeatmap {
  const row = recordOf(value, fn);

  return {
    matrix: matrixOf(row["matrix"], fn),
    basis: row["basis"] === "inherent" ? "inherent" : "residual",
    cells: recordsOf(row["cells"], fn).map((cell) => ({
      likelihood: numberOf(cell["likelihood"]),
      impact: numberOf(cell["impact"]),
      score: numberOf(cell["score"]),
      band: textOf(cell["band"]),
      count: numberOf(cell["count"]),
      riskIds: Array.isArray(cell["riskIds"])
        ? cell["riskIds"].map((id) => textOf(id))
        : [],
    })),
  };
}

const definedOf = (input: object): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(input).filter(([, value]) => value !== undefined),
  );

/**
 * A risk register: risks scored on a likelihood by impact matrix before and
 * after controls, treated, reviewed and closed.
 */
export function createRisks<S extends StandardSchemaV1 | undefined = undefined>(
  options: RisksOptions<S>,
): Risks<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);
  const fields: BlockFields<F> = blockFields(options.fields, "risk fields");
  const risk = (fn: string) => (value: unknown) => riskOf(value, fn);

  const withFields = (
    input: object & { readonly fields?: Partial<F> },
  ): AsyncResult<Record<string, unknown>> =>
    fields
      .args(input.fields)
      .map((checked) => ({
        ...definedOf(input),
        ...(checked === undefined ? {} : { fields: checked }),
      }));

  const client: Risks<F> = {
    saveMatrix: (input) =>
      tenant().andThen((organizationId) =>
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
            matrix_id: input.matrixId ?? null,
          },
          (value) => matrixOf(value, "save_risk_matrix"),
        ),
      ),
    matrices: () =>
      tenant().andThen((organizationId) =>
        call("list_risk_matrices", { tenant: organizationId }, (value) =>
          recordsOf(value, "list_risk_matrices").map((row) =>
            matrixOf(row, "list_risk_matrices"),
          ),
        ),
      ),
    create: (input) =>
      tenant().andThen((organizationId) =>
        withFields(input).andThen((attrs) =>
          call(
            "create_risk",
            { tenant: organizationId, input: attrs },
            risk("create_risk"),
          ).andThen(fields.row),
        ),
      ),
    update: (riskId, change) =>
      withFields(change).andThen((attrs) =>
        call(
          "update_risk",
          { risk_id: riskId, changes: attrs },
          risk("update_risk"),
        ).andThen(fields.row),
      ),
    assess: (riskId, input) =>
      call(
        "assess_risk",
        {
          risk_id: riskId,
          inherent_likelihood: input.inherent.likelihood,
          inherent_impact: input.inherent.impact,
          residual_likelihood: input.residual.likelihood,
          residual_impact: input.residual.impact,
          rationale: input.rationale ?? null,
        },
        risk("assess_risk"),
      ).andThen(fields.row),
    setTreatment: (riskId, treatment, note) =>
      call(
        "set_risk_treatment",
        { risk_id: riskId, treatment, note: note ?? null },
        risk("set_risk_treatment"),
      ).andThen(fields.row),
    review: (riskId, note) =>
      call(
        "review_risk",
        { risk_id: riskId, note: note ?? null },
        risk("review_risk"),
      ).andThen(fields.row),
    close: (riskId, reason) =>
      call(
        "close_risk",
        { risk_id: riskId, reason },
        risk("close_risk"),
      ).andThen(fields.row),
    get: (riskId) =>
      call("get_risk", { risk_id: riskId }, (value) =>
        detailOf(value, "get_risk"),
      ).andThen(fields.row),
    list: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_risks",
          { tenant: organizationId, filters: definedOf(list) },
          (value) =>
            recordsOf(value, "list_risks").map((row) =>
              riskOf(row, "list_risks"),
            ),
        ).andThen(fields.rows),
      ),
    heatmap: (heatmap = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "risk_heatmap",
          {
            tenant: organizationId,
            matrix_id: heatmap.matrixId ?? null,
            basis: heatmap.basis ?? "residual",
          },
          (value) => heatmapOf(value, "risk_heatmap"),
        ),
      ),
    notifyDueReviews: () =>
      call("notify_due_risk_reviews", {}, (value) => numberOf(value)),
  };

  return withBlockHooks(client, options.hooks, {
    block: "risks",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
