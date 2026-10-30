import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";

/** The keys the observation reads return next to the extra columns. */
export const OBSERVATION_RESERVED = [
  "fields",
  "value",
  "definitionKey",
  "valueType",
  "unit",
] as const;

/** What a definition's value is. */
export const VALUE_TYPES = [
  "number",
  "integer",
  "boolean",
  "code",
  "text",
  "components",
] as const;

/** How a value compares with its definition's ranges. */
export const FLAGS = [
  "normal",
  "low",
  "high",
  "critical_low",
  "critical_high",
] as const;

/** An observation's status, as FHIR R4 Observation.status names them. */
export const STATUSES = ["final", "amended", "entered_in_error"] as const;

/** Where an observation came from. */
export const SOURCES = ["manual", "form", "device", "import"] as const;

/** The series buckets `observation_series` groups by. */
export const BUCKETS = ["hour", "day", "week", "month"] as const;

/** The code system of the shipped vital signs. */
export const LOINC = "http://loinc.org";

/** The `defaults` option values. */
export const DEFAULT_SETS = ["none", "vitals"] as const;

/** A component of a `components` definition, as the definition stores it. */
interface VitalComponent {
  readonly key: string;
  readonly title: string;
  readonly unit: string;
  readonly code: string;
  readonly validLow: number;
  readonly validHigh: number;
  readonly referenceLow?: number;
  readonly referenceHigh?: number;
  readonly criticalLow?: number;
  readonly criticalHigh?: number;
}

/** A shipped system definition. */
interface Vital {
  readonly key: string;
  readonly title: string;
  readonly valueType: "number" | "integer" | "components";
  readonly unit?: string;
  readonly code: string;
  readonly decimals?: number;
  readonly validLow?: number;
  readonly validHigh?: number;
  readonly referenceLow?: number;
  readonly referenceHigh?: number;
  readonly criticalLow?: number;
  readonly criticalHigh?: number;
  readonly components?: readonly VitalComponent[];
}

/**
 * The vital signs `defaults: "vitals"` installs as system definitions: UCUM
 * units and the LOINC codes of the FHIR R4 vital signs profile. The ranges are
 * adult defaults; an organization tightens them by saving its own definition
 * with the same key.
 */
export const VITALS: readonly Vital[] = [
  {
    key: "heart_rate",
    title: "Heart rate",
    valueType: "integer",
    unit: "/min",
    code: "8867-4",
    validLow: 0,
    validHigh: 350,
    referenceLow: 51,
    referenceHigh: 90,
    criticalLow: 40,
    criticalHigh: 131,
  },
  {
    key: "blood_pressure",
    title: "Blood pressure",
    valueType: "components",
    code: "85354-9",
    components: [
      {
        key: "systolic",
        title: "Systolic",
        unit: "mm[Hg]",
        code: "8480-6",
        validLow: 0,
        validHigh: 350,
        referenceLow: 100,
        referenceHigh: 140,
        criticalLow: 90,
        criticalHigh: 220,
      },
      {
        key: "diastolic",
        title: "Diastolic",
        unit: "mm[Hg]",
        code: "8462-4",
        validLow: 0,
        validHigh: 250,
        referenceLow: 60,
        referenceHigh: 90,
        criticalLow: 40,
        criticalHigh: 130,
      },
    ],
  },
  {
    key: "body_temperature",
    title: "Body temperature",
    valueType: "number",
    unit: "Cel",
    code: "8310-5",
    decimals: 1,
    validLow: 20,
    validHigh: 46,
    referenceLow: 36.1,
    referenceHigh: 38,
    criticalLow: 35,
    criticalHigh: 39.1,
  },
  {
    key: "respiratory_rate",
    title: "Respiratory rate",
    valueType: "integer",
    unit: "/min",
    code: "9279-1",
    validLow: 0,
    validHigh: 100,
    referenceLow: 12,
    referenceHigh: 20,
    criticalLow: 8,
    criticalHigh: 25,
  },
  {
    key: "oxygen_saturation",
    title: "Oxygen saturation",
    valueType: "integer",
    unit: "%",
    code: "2708-6",
    validLow: 0,
    validHigh: 100,
    referenceLow: 96,
    criticalLow: 91,
  },
  {
    key: "body_weight",
    title: "Body weight",
    valueType: "number",
    unit: "kg",
    code: "29463-7",
    decimals: 1,
    validLow: 0,
    validHigh: 700,
  },
  {
    key: "body_height",
    title: "Body height",
    valueType: "number",
    unit: "cm",
    code: "8302-2",
    decimals: 1,
    validLow: 0,
    validHigh: 300,
  },
  {
    key: "pain_score",
    title: "Pain score",
    valueType: "integer",
    unit: "{score}",
    code: "72514-3",
    validLow: 0,
    validHigh: 10,
    referenceHigh: 3,
  },
  {
    key: "blood_glucose",
    title: "Blood glucose",
    valueType: "number",
    unit: "mmol/L",
    code: "15074-8",
    decimals: 1,
    validLow: 0,
    validHigh: 60,
    referenceLow: 4,
    referenceHigh: 7.8,
    criticalLow: 3,
    criticalHigh: 20,
  },
];

/** The checked `blocks.observations.options.defaults`. */
export function defaultSet(ctx: BlockSqlContext): "none" | "vitals" {
  const value = ctx.text("defaults", "none");

  if (value !== "none" && value !== "vitals") {
    throw new TypeError(
      `blocks.observations.options.defaults takes ${DEFAULT_SETS.join(" or ")}, not ${value}`,
    );
  }

  return value;
}

/**
 * Whether the managed observations table is partitioned by month on
 * `created_at` (ADR 0038). An app's own table keeps its shape.
 */
export const observationsPartitioned = (ctx: BlockSqlContext): boolean =>
  ctx.owns("observations") && ctx.flag("partitioned", false);

/** `('a', 'b')` for an `in` list. */
/** Whether forms keeps submissions, which observations can come from. */
export const observationForms = (ctx: BlockSqlContext): boolean =>
  ctx.installed("forms") && ctx.of("forms").owns("submissions");

export const sqlList = (values: readonly string[]): string =>
  `(${values.map((value) => sqlString(value)).join(", ")})`;

/** `row.column`, or null when the app's table lacks the optional column. */
export const optionalField = (
  ctx: BlockSqlContext,
  table: string,
  row: string,
  column: string,
): string =>
  ctx.has(table, column) ? `${row}.${ctx.col(table, column)}` : "null";

/** A numeric SQL literal, or `null`. */
const num = (value: number | undefined): string =>
  value === undefined ? "null" : String(value);

/** A shipped component as the jsonb a definition stores. */
function componentJson(component: VitalComponent): string {
  const entries: Record<string, string | number> = {
    key: component.key,
    title: component.title,
    unit: component.unit,
    code: component.code,
    validLow: component.validLow,
    validHigh: component.validHigh,
  };

  for (const key of [
    "referenceLow",
    "referenceHigh",
    "criticalLow",
    "criticalHigh",
  ] as const) {
    const value = component[key];

    if (value !== undefined) {
      entries[key] = value;
    }
  }

  return JSON.stringify(entries);
}

/**
 * Row SQL for `data`: the system definitions of `defaults: "vitals"`, kept when
 * they are there already.
 */
export function vitalsData(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom" || defaultSet(ctx) !== "vitals") {
    return "";
  }

  const d = (column: string): string => ctx.col("definitions", column);

  const rows = VITALS.map((vital) => {
    const components =
      vital.components === undefined
        ? "null"
        : `${sqlString(`[${vital.components.map(componentJson).join(", ")}]`)}::jsonb`;

    return `  (null, ${sqlString(vital.key)}, ${sqlString(vital.title)}, ${sqlString(vital.valueType)}, ${vital.unit === undefined ? "null" : sqlString(vital.unit)}, ${sqlString(LOINC)}, ${sqlString(vital.code)}, ${components}, ${num(vital.decimals)}, ${num(vital.validLow)}, ${num(vital.validHigh)}, ${num(vital.referenceLow)}, ${num(vital.referenceHigh)}, ${num(vital.criticalLow)}, ${num(vital.criticalHigh)})`;
  }).join(",\n");

  return `
-- blocks.observations.options.defaults: the vital signs, as system
-- definitions every organization reads.
insert into ${ctx.table("definitions")} (${d("tenant")}, ${d("key")}, ${d("title")}, ${d("valueType")}, ${d("unit")}, ${d("codeSystem")}, ${d("code")}, ${d("components")}, ${d("decimals")}, ${d("validLow")}, ${d("validHigh")}, ${d("referenceLow")}, ${d("referenceHigh")}, ${d("criticalLow")}, ${d("criticalHigh")})
values
${rows}
on conflict (${d("tenant")}, ${d("key")}) do nothing;
`;
}
