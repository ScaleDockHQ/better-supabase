import type { BlockSqlContext } from "../context.ts";

import { columnRef } from "../shared.ts";

const ENTITY = /^[a-z][a-z0-9_]*$/;
const PREDICATE = /^[A-Za-z0-9_.'"=<>!(), \t-]+$/;
const QUOTED = /'(?:[^']|'')*'|"(?:[^"]|"")*"/g;
const LITERAL = String.raw`(?:\x01|-?[0-9]+(?:\.[0-9]+)?)`;

const IN_LIST = new RegExp(
  String.raw`\bin\s*\(\s*${LITERAL}(?:\s*,\s*${LITERAL})*\s*\)`,
  "gi",
);

function isPredicate(text: string): boolean {
  if (!PREDICATE.test(text)) {
    return false;
  }

  const bare = text.replaceAll(QUOTED, (quoted) =>
    quoted.startsWith("'") ? "\u0001" : "\u0002",
  );

  return !/['",]/.test(bare.replaceAll(IN_LIST, "in (\u0001)"));
}

export interface TenantColumn {
  readonly table: string;
  readonly column: string;
  readonly key: string;
}

export interface SequenceEntity {
  readonly name: string;
  readonly period: "none" | "year" | "month" | "fiscal" | "format";
  readonly fiscalMonth: number;
  readonly format: string;
  readonly formatFrom?: TenantColumn;
  readonly periodFrom?: TenantColumn;
  readonly table?: string;
  readonly column?: string;
  readonly sequenceColumn?: string;
  readonly tenantColumn: string;
  readonly assignOn: string;
  readonly periodColumn?: string;
  readonly permission?: string;
}

const YEAR_TOKEN = /\{yy(?:yy)?\}/;

function formatPeriod(format: string): "none" | "year" | "month" {
  if (!YEAR_TOKEN.test(format)) {
    return "none";
  }

  return format.includes("{mm}") ? "month" : "year";
}

function tenantSource(where: string, value: unknown): TenantColumn | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TypeError(
      `${where} must be { column: "schema.table.column", key? }`,
    );
  }

  const record = recordOf(value);
  const column = record["column"];
  const key = record["key"] ?? "id";

  if (typeof column !== "string") {
    throw new TypeError(`${where}.column must be "schema.table.column"`);
  }

  if (typeof key !== "string" || !ENTITY.test(key)) {
    throw new TypeError(`${where}.key must be a column name`);
  }

  return { ...columnRef(`${where}.column`, column), key };
}

export function sequences(ctx: BlockSqlContext): readonly SequenceEntity[] {
  const raw = ctx.option("entities");

  if (raw === undefined) {
    return [];
  }

  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new TypeError(
      "blocks.numbering.options.entities must be an object of entity name to { period, format }",
    );
  }

  return Object.entries(raw).map(([name, entry]) => entity(name, entry));
}

function entity(name: string, entry: unknown): SequenceEntity {
  const where = `blocks.numbering.options.entities.${name}`;

  if (!ENTITY.test(name)) {
    throw new TypeError(
      `${where}: "${name}" must be lowercase letters, digits and underscores`,
    );
  }

  if (typeof entry !== "object" || entry === null || Array.isArray(entry)) {
    throw new TypeError(`${where} must be an object`);
  }

  const record = recordOf(entry);
  const period = record["period"];

  const fiscal =
    typeof period === "object" && period !== null && !Array.isArray(period)
      ? recordOf(period)["fiscalYearStartMonth"]
      : undefined;

  const stated =
    period === "none" ||
    period === "year" ||
    period === "month" ||
    period === "format"
      ? period
      : fiscal === undefined
        ? undefined
        : "fiscal";

  if (stated === undefined) {
    throw new TypeError(
      `${where}.period must be "none", "year", "month", "format" or { fiscalYearStartMonth }`,
    );
  }

  const fiscalMonth = stated === "fiscal" ? Number(fiscal) : 1;

  if (
    stated === "fiscal" &&
    (!Number.isInteger(fiscalMonth) || fiscalMonth < 1 || fiscalMonth > 12)
  ) {
    throw new TypeError(
      `${where}.period.fiscalYearStartMonth must be an integer from 1 to 12`,
    );
  }

  const format = record["format"];

  if (typeof format !== "string" || format.length === 0 || format.length > 80) {
    throw new TypeError(`${where}.format must be a short template`);
  }

  const formatFrom = tenantSource(`${where}.formatFrom`, record["formatFrom"]);
  const periodFrom = tenantSource(`${where}.periodFrom`, record["periodFrom"]);

  const kind =
    stated === "format" && formatFrom === undefined
      ? formatPeriod(format)
      : stated;

  const table = record["table"];
  const column = record["column"];

  if (table !== undefined && typeof table !== "string") {
    throw new TypeError(`${where}.table must be "schema.table"`);
  }

  if (
    column !== undefined &&
    (typeof column !== "string" || !ENTITY.test(column))
  ) {
    throw new TypeError(`${where}.column must be a column name`);
  }

  if ((table === undefined) !== (column === undefined)) {
    throw new TypeError(`${where} needs both table and column, or neither`);
  }

  const sequenceColumn = record["sequenceColumn"];

  if (
    sequenceColumn !== undefined &&
    (typeof sequenceColumn !== "string" ||
      !ENTITY.test(sequenceColumn) ||
      column === undefined ||
      sequenceColumn === column)
  ) {
    throw new TypeError(
      `${where}.sequenceColumn must be a column name other than column, with table and column set`,
    );
  }

  const tenantColumn = record["tenantColumn"] ?? "tenant_id";

  if (typeof tenantColumn !== "string" || !ENTITY.test(tenantColumn)) {
    throw new TypeError(`${where}.tenantColumn must be a column name`);
  }

  const periodColumn = record["periodColumn"];

  if (
    periodColumn !== undefined &&
    (typeof periodColumn !== "string" || !ENTITY.test(periodColumn))
  ) {
    throw new TypeError(`${where}.periodColumn must be a column name`);
  }

  const permission = record["permission"];

  if (
    permission !== undefined &&
    (typeof permission !== "string" ||
      permission.length === 0 ||
      permission.length > 200)
  ) {
    throw new TypeError(`${where}.permission must be a permission key`);
  }

  const assignOn = record["assignOn"] ?? "true";

  if (typeof assignOn !== "string" || !isPredicate(assignOn)) {
    throw new TypeError(
      `${where}.assignOn must be a boolean expression over new, such as new.status = 'sent' or new.status in ('sent', 'overdue')`,
    );
  }

  return {
    name,
    period: kind,
    fiscalMonth,
    format,
    ...(formatFrom === undefined ? {} : { formatFrom }),
    ...(periodFrom === undefined ? {} : { periodFrom }),
    ...(typeof table === "string" && typeof column === "string"
      ? { table, column }
      : {}),
    ...(typeof sequenceColumn === "string" ? { sequenceColumn } : {}),
    tenantColumn,
    assignOn,
    ...(typeof periodColumn === "string" ? { periodColumn } : {}),
    ...(typeof permission === "string" ? { permission } : {}),
  };
}

function recordOf(value: object): Record<string, unknown> {
  const record: Record<string, unknown> = {};

  for (const [key, item] of Object.entries(value)) {
    record[key] = item;
  }

  return record;
}
