import type { BlockSqlContext, ExtraColumn } from "../context.ts";

import { isRecord } from "../../core/guards.ts";
import { sqlString } from "../../core/template.ts";
import { extraFieldsJson, fail, SERVICE_CALLER } from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";

const WHERE = "blocks.risks.options";

/** The statuses a risk moves through. */
export const RISK_STATUSES = [
  "identified",
  "assessed",
  "treating",
  "accepted",
  "closed",
] as const;

/** How a risk is treated. */
export const RISK_TREATMENTS = [
  "mitigate",
  "accept",
  "transfer",
  "avoid",
] as const;

/** How a matrix turns a likelihood and an impact into a score. */
export const RISK_SCORINGS = ["product", "sum"] as const;

/** The keys the risk reads return next to the extra columns. */
const RISK_RESERVED = ["fields", "inherent", "residual", "matrix"] as const;

const DEFAULT_CATEGORIES: readonly string[] = [
  "quality",
  "safety",
  "environment",
  "security",
  "compliance",
  "operational",
  "financial",
  "strategic",
];

/** A level of a matrix axis. */
export interface RiskMatrixLevel {
  readonly value: number;
  readonly label: string;
}

/** A band of scores, such as `high` for 10 to 16. */
export interface RiskMatrixBand {
  readonly key: string;
  readonly label: string;
  readonly min: number;
  readonly max: number;
}

/** `options.defaultMatrix`: the matrix each organization starts with. */
export interface RiskMatrixDefinition {
  readonly key: string;
  readonly name: string;
  readonly likelihoodLevels: readonly RiskMatrixLevel[];
  readonly impactLevels: readonly RiskMatrixLevel[];
  readonly bands: readonly RiskMatrixBand[];
  readonly scoring: (typeof RISK_SCORINGS)[number];
}

const levels = (labels: readonly string[]): readonly RiskMatrixLevel[] =>
  labels.map((label, index) => ({ value: index + 1, label }));

/** A 5 by 5 matrix scored as likelihood times impact, in four bands. */
export const DEFAULT_RISK_MATRIX: RiskMatrixDefinition = {
  key: "default",
  name: "Default 5x5",
  likelihoodLevels: levels([
    "Rare",
    "Unlikely",
    "Possible",
    "Likely",
    "Almost certain",
  ]),
  impactLevels: levels([
    "Insignificant",
    "Minor",
    "Moderate",
    "Major",
    "Severe",
  ]),
  bands: [
    { key: "low", label: "Low", min: 1, max: 4 },
    { key: "medium", label: "Medium", min: 5, max: 9 },
    { key: "high", label: "High", min: 10, max: 16 },
    { key: "critical", label: "Critical", min: 17, max: 25 },
  ],
  scoring: "product",
};

const CATEGORY = /^[a-z][a-z0-9_-]{0,62}$/;
const MATRIX_KEY = /^[a-z][a-z0-9_-]{0,62}$/;
const BAND_KEY = /^[a-z][a-z0-9_]{0,31}$/;

/** The lowest and highest score a matrix of these sizes can give. */
function scoreRange(
  likelihoods: number,
  impacts: number,
  scoring: string,
): { readonly min: number; readonly max: number } {
  return scoring === "sum"
    ? { min: 2, max: likelihoods + impacts }
    : { min: 1, max: likelihoods * impacts };
}

function levelsProblem(value: unknown, what: string): string | undefined {
  if (!Array.isArray(value) || value.length < 2 || value.length > 10) {
    return `${what} must be a list of 2 to 10 levels`;
  }

  const seen = value.map((level) =>
    isRecord(level) &&
    Number.isInteger(level["value"]) &&
    typeof level["label"] === "string" &&
    level["label"].trim().length > 0 &&
    level["label"].length <= 100
      ? Number(level["value"])
      : 0,
  );

  const expected = value.map((_, index) => index + 1);
  const sorted = seen.toSorted((a, b) => a - b);

  return sorted.every((level, index) => level === expected[index])
    ? undefined
    : `${what} values must be 1 to n, each once, with a label of 1 to 100 characters`;
}

function bandsProblem(
  value: unknown,
  range: { readonly min: number; readonly max: number },
): string | undefined {
  if (!Array.isArray(value) || value.length === 0 || value.length > 10) {
    return "bands must be a list of 1 to 10 bands";
  }

  const bands: RiskMatrixBand[] = [];

  for (const band of value) {
    if (
      !isRecord(band) ||
      typeof band["key"] !== "string" ||
      !BAND_KEY.test(band["key"]) ||
      typeof band["label"] !== "string" ||
      band["label"].trim().length === 0 ||
      band["label"].length > 100 ||
      !Number.isInteger(band["min"]) ||
      !Number.isInteger(band["max"])
    ) {
      return "each band needs a key of lowercase letters, digits and underscores, a label, and whole-number min and max";
    }

    bands.push({
      key: band["key"],
      label: band["label"],
      min: Number(band["min"]),
      max: Number(band["max"]),
    });
  }

  if (new Set(bands.map((band) => band.key)).size !== bands.length) {
    return "band keys must be unique";
  }

  const sorted = bands.toSorted((a, b) => a.min - b.min);
  let next = range.min;

  for (const band of sorted) {
    if (band.min !== next || band.max < band.min) {
      return "bands must cover every score from the lowest to the highest without gaps or overlaps";
    }

    next = band.max + 1;
  }

  return next === range.max + 1
    ? undefined
    : "bands must cover every score from the lowest to the highest without gaps or overlaps";
}

/** Why `value` is not a valid matrix, or undefined when it is. */
export function riskMatrixProblem(value: unknown): string | undefined {
  if (!isRecord(value)) {
    return "a matrix must be an object";
  }

  if (typeof value["key"] !== "string" || !MATRIX_KEY.test(value["key"])) {
    return "key must be lowercase letters, digits, dashes and underscores";
  }

  if (
    typeof value["name"] !== "string" ||
    value["name"].trim().length === 0 ||
    value["name"].length > 200
  ) {
    return "name must be 1 to 200 characters";
  }

  const scoring = value["scoring"] ?? "product";

  if (scoring !== "product" && scoring !== "sum") {
    return "scoring must be product or sum";
  }

  const likelihood = levelsProblem(
    value["likelihoodLevels"],
    "likelihoodLevels",
  );

  const impact = levelsProblem(value["impactLevels"], "impactLevels");

  if (likelihood !== undefined || impact !== undefined) {
    return likelihood ?? impact;
  }

  const count = (key: string): number => {
    const list = value[key];

    return Array.isArray(list) ? list.length : 0;
  };

  return bandsProblem(
    value["bands"],
    scoreRange(count("likelihoodLevels"), count("impactLevels"), scoring),
  );
}

/** `options.defaultMatrix`, checked; the 5 by 5 matrix when left out. */
function defaultMatrixOf(ctx: BlockSqlContext): RiskMatrixDefinition {
  const raw = ctx.option("defaultMatrix");

  if (raw === undefined) {
    return DEFAULT_RISK_MATRIX;
  }

  const problem = riskMatrixProblem(raw);

  if (problem !== undefined) {
    throw new TypeError(`${WHERE}.defaultMatrix: ${problem}`);
  }

  // SAFETY: riskMatrixProblem checked every key RiskMatrixDefinition has;
  // scoring may be left out and defaults to product.
  const matrix = raw as Omit<RiskMatrixDefinition, "scoring"> & {
    readonly scoring?: RiskMatrixDefinition["scoring"];
  };

  return { ...matrix, scoring: matrix.scoring ?? "product" };
}

/** `options.categories`, checked. */
function riskCategories(ctx: BlockSqlContext): readonly string[] {
  const values = ctx.list("categories", DEFAULT_CATEGORIES);

  if (values.length === 0) {
    throw new TypeError(`${WHERE}.categories must name at least one category`);
  }

  for (const value of values) {
    if (!CATEGORY.test(value)) {
      throw new TypeError(
        `${WHERE}.categories: "${value}" must be lowercase letters, digits, dashes and underscores`,
      );
    }
  }

  if (new Set(values).size !== values.length) {
    throw new TypeError(`${WHERE}.categories lists a category twice`);
  }

  return values;
}

/** The SQL pieces the risks files share. */
export interface RisksSql {
  readonly fn: (name: string) => string;
  /** A column of the matrices table. */
  readonly m: (column: string) => string;
  /** A column of the risks table. */
  readonly r: (column: string) => string;
  /** A column of the assessments table. */
  readonly a: (column: string) => string;
  /** `row.column` of a risks row, or `null` when the table lacks it. */
  readonly riskOf: (row: string, column: string) => string;
  /** `row.column` of an assessments row, or `null` when the table lacks it. */
  readonly assessmentOf: (row: string, column: string) => string;
  readonly has: (table: string, column: string) => boolean;
  readonly matrices: string;
  readonly risks: string;
  readonly assessments: string;
  readonly extras: readonly ExtraColumn[];
  /** The risks' subject type, after renames, as a SQL literal. */
  readonly subject: string;
  /** `options.categories` as a SQL `text[]` literal. */
  readonly categories: string;
  readonly defaultMatrix: RiskMatrixDefinition;
  readonly versions: BlockSqlContext;
  /** The relations context, when its table is there to read links from. */
  readonly relations: BlockSqlContext | undefined;
  readonly read: string;
  readonly write: string;
  readonly assess: string;
  readonly manage: string;
  readonly allowed: (tenant: string, permission: string) => string;
  readonly invalid: (message: string) => string;
  readonly forbidden: (message: string) => string;
  readonly missing: string;
  readonly closed: string;
  readonly matrixMissing: string;
  /** The score of `likelihood` and `impact` on matrix row `matrix`. */
  readonly score: (
    matrix: string,
    likelihood: string,
    impact: string,
  ) => string;
  /** The key of the band of matrix row `matrix` that holds `score`. */
  readonly band: (matrix: string, score: string) => string;
  readonly matrixJson: (row: string) => string;
  readonly riskJson: (row: string) => string;
  readonly assessmentJson: (row: string) => string;
  /**
   * Records a `risk.*` event of a risks row with `extra` keys added to the
   * payload; `summary` false leaves it out of the audit log.
   */
  readonly record: (
    type: string,
    row: string,
    summary: string | false,
    extra?: string,
  ) => string;
  /** Records a `risk_matrix.*` event of a matrices row. */
  readonly recordMatrix: (type: string, row: string, summary: string) => string;
}

const textArray = (values: readonly string[]): string =>
  `array[${values.map((value) => sqlString(value)).join(", ")}]::text[]`;

export function risksSql(ctx: BlockSqlContext): RisksSql {
  const m = (column: string): string => ctx.col("matrices", column);
  const r = (column: string): string => ctx.col("risks", column);
  const a = (column: string): string => ctx.col("assessments", column);

  const has = (table: string, column: string): boolean =>
    ctx.has(table, column);

  const riskOf = (row: string, column: string): string =>
    has("risks", column) ? `${row}.${r(column)}` : "null";

  const assessmentOf = (row: string, column: string): string =>
    has("assessments", column) ? `${row}.${a(column)}` : "null";

  const extras = ctx.extraColumns("risks", RISK_RESERVED);

  const relations =
    ctx.installed("relations") && ctx.of("relations").mode !== "custom"
      ? ctx.of("relations")
      : undefined;

  const axis = (row: string, side: "inherent" | "residual"): string =>
    `case when ${row}.${r(`${side}Score`)} is null then null else jsonb_build_object('likelihood', ${row}.${r(`${side}Likelihood`)}, 'impact', ${row}.${r(`${side}Impact`)}, 'score', ${row}.${r(`${side}Score`)}, 'band', ${row}.${r(`${side}Band`)}) end`;

  const assessed = (row: string, side: "inherent" | "residual"): string =>
    `jsonb_build_object('likelihood', ${row}.${a(`${side}Likelihood`)}, 'impact', ${row}.${a(`${side}Impact`)}, 'score', ${row}.${a(`${side}Score`)}, 'band', ${row}.${a(`${side}Band`)})`;

  return {
    fn: (name) => ctx.fn(name),
    m,
    r,
    a,
    riskOf,
    assessmentOf,
    has,
    matrices: ctx.table("matrices"),
    risks: ctx.table("risks"),
    assessments: ctx.table("assessments"),
    extras,
    subject: sqlString(ctx.naming.rename("risk")),
    categories: textArray(riskCategories(ctx)),
    defaultMatrix: defaultMatrixOf(ctx),
    versions: ctx.of("versions"),
    relations,
    read: ctx.permission("read", OPERATIONS["risks.read"]),
    write: ctx.permission("write", OPERATIONS["risks.write"]),
    assess: ctx.permission("assess", OPERATIONS["risks.assess"]),
    manage: ctx.permission("manage", OPERATIONS["risks.manage"]),
    allowed: (tenant, permission) =>
      `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`,
    invalid: (message) => fail("RISK_INVALID", message, "22023"),
    forbidden: (message) => fail("RISK_FORBIDDEN", message),
    missing: fail("RISK_NOT_FOUND", "no such risk", "P0002"),
    closed: fail("RISK_CLOSED", "the risk is closed", "55000"),
    matrixMissing: fail(
      "RISK_MATRIX_NOT_FOUND",
      "no such risk matrix in this organization",
      "P0002",
    ),
    score: (matrix, likelihood, impact) =>
      `(case when ${matrix}.${m("scoring")} = 'sum' then ${likelihood} + ${impact} else ${likelihood} * ${impact} end)`,
    band: (matrix, score) =>
      `(select b ->> 'key' from jsonb_array_elements(${matrix}.${m("bands")}) b where ${score} between (b ->> 'min')::integer and (b ->> 'max')::integer limit 1)`,
    matrixJson: (row) =>
      `jsonb_build_object('id', ${row}.${m("id")}, 'organizationId', ${row}.${m("tenant")}, 'key', ${row}.${m("key")}, 'name', ${row}.${m("name")}, 'likelihoodLevels', ${row}.${m("likelihoodLevels")}, 'impactLevels', ${row}.${m("impactLevels")}, 'bands', ${row}.${m("bands")}, 'scoring', ${row}.${m("scoring")}, 'isDefault', ${row}.${m("isDefault")}, 'createdAt', ${row}.${m("createdAt")}, 'updatedAt', ${row}.${m("updatedAt")})`,
    riskJson: (row) =>
      `jsonb_build_object('id', ${row}.${r("id")}, 'organizationId', ${row}.${r("tenant")}, 'number', ${row}.${r("number")}, 'matrixId', ${row}.${r("matrix")}, 'title', ${row}.${r("title")}, 'description', ${riskOf(row, "description")}, 'category', ${row}.${r("category")}, 'cause', ${riskOf(row, "cause")}, 'consequence', ${riskOf(row, "consequence")}, 'ownerId', ${row}.${r("owner")}, 'status', ${row}.${r("status")}, 'treatment', ${row}.${r("treatment")}, 'reviewIntervalMonths', ${row}.${r("reviewIntervalMonths")}, 'nextReviewOn', ${row}.${r("nextReviewOn")}, 'reviewedAt', ${row}.${r("reviewedAt")}, 'inherent', ${axis(row, "inherent")}, 'residual', ${axis(row, "residual")}, 'currentAssessmentId', ${row}.${r("currentAssessment")}, 'closedAt', ${row}.${r("closedAt")}, 'archivedAt', ${row}.${r("archivedAt")}, 'createdBy', ${riskOf(row, "createdBy")}, 'createdAt', ${row}.${r("createdAt")}, 'updatedAt', ${row}.${r("updatedAt")}${extraFieldsJson(row, extras)})`,
    assessmentJson: (row) =>
      `jsonb_build_object('id', ${row}.${a("id")}, 'organizationId', ${row}.${a("tenant")}, 'riskId', ${row}.${a("risk")}, 'inherent', ${assessed(row, "inherent")}, 'residual', ${assessed(row, "residual")}, 'rationale', ${assessmentOf(row, "rationale")}, 'versionId', ${assessmentOf(row, "version")}, 'assessedBy', ${row}.${a("assessedBy")}, 'assessedAt', ${row}.${a("assessedAt")})`,
    record: (type, row, summary, extra = "") =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${r("tenant")}, 'id', ${row}.${r("id")}, 'number', ${row}.${r("number")}, 'title', ${row}.${r("title")}, 'status', ${row}.${r("status")}${extra})`,
        subject: `'risks/' || ${row}.${r("id")}::text`,
        tenant: `${row}.${r("tenant")}`,
        audit:
          summary === false
            ? false
            : {
                category: "data",
                targetType: "risk",
                recordId: `${row}.${r("id")}::text`,
                targetLabel: `${row}.${r("title")}`,
                summary: sqlString(summary),
              },
      }),
    recordMatrix: (type, row, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${m("tenant")}, 'id', ${row}.${m("id")}, 'key', ${row}.${m("key")}, 'name', ${row}.${m("name")}, 'isDefault', ${row}.${m("isDefault")})`,
        subject: `'risk-matrices/' || ${row}.${m("id")}::text`,
        tenant: `${row}.${m("tenant")}`,
        audit: {
          category: "data",
          targetType: "risk_matrix",
          recordId: `${row}.${m("id")}::text`,
          targetLabel: `${row}.${m("name")}`,
          summary: sqlString(summary),
        },
      }),
  };
}
