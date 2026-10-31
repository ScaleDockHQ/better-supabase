import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER } from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";

/** A block context of another module, when it is installed and not custom. */
function linked(
  ctx: BlockSqlContext,
  module: string,
): BlockSqlContext | undefined {
  return ctx.installed(module) && ctx.of(module).mode !== "custom"
    ? ctx.of(module)
    : undefined;
}

/** The SQL pieces the lims files share. */
export interface LimsSql {
  readonly fn: (name: string) => string;
  /** A column of the methods table. */
  readonly m: (column: string) => string;
  /** A column of the samples table. */
  readonly s: (column: string) => string;
  /** A column of the results table. */
  readonly r: (column: string) => string;
  readonly methods: string;
  readonly samples: string;
  readonly results: string;
  readonly subject: string;
  readonly read: string;
  readonly write: string;
  readonly manage: string;
  readonly allowed: (tenant: string, permission: string) => string;
  readonly invalid: (message: string) => string;
  readonly forbidden: (message: string) => string;
  readonly sampleMissing: string;
  readonly methodMissing: string;
  readonly forms: BlockSqlContext | undefined;
  readonly cases: BlockSqlContext | undefined;
  readonly assets: BlockSqlContext | undefined;
  readonly qualifications: BlockSqlContext | undefined;
  /** `options.instrumentQualification`, or undefined. */
  readonly instrumentQualification: string | undefined;
  /** `options.nonconformityKind`. */
  readonly nonconformityKind: string;
  readonly methodJson: (row: string) => string;
  readonly sampleJson: (row: string) => string;
  readonly resultJson: (row: string) => string;
  /** Records a `lims_sample.*` event of a samples row. */
  readonly recordSample: (type: string, row: string, summary: string) => string;
  /** Records a `lims_result.*` event of a results row of sample `sample`. */
  readonly recordResult: (
    type: string,
    row: string,
    sample: string,
    summary: string,
  ) => string;
}

export function limsSql(ctx: BlockSqlContext): LimsSql {
  const m = (column: string): string => ctx.col("methods", column);
  const s = (column: string): string => ctx.col("samples", column);
  const r = (column: string): string => ctx.col("results", column);

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`;

  const qualification = ctx.option("instrumentQualification");
  const kind = ctx.option("nonconformityKind");

  if (
    typeof qualification === "string" &&
    qualification !== "" &&
    (linked(ctx, "qualifications") === undefined ||
      linked(ctx, "assets") === undefined)
  ) {
    throw new TypeError(
      "blocks.lims.options.instrumentQualification needs the assets and qualifications blocks",
    );
  }

  return {
    fn: (name) => ctx.fn(name),
    m,
    s,
    r,
    methods: ctx.table("methods"),
    samples: ctx.table("samples"),
    results: ctx.table("results"),
    subject: sqlString(ctx.naming.rename("lims_sample")),
    read: ctx.permission("read", OPERATIONS["lims.read"]),
    write: ctx.permission("write", OPERATIONS["lims.write"]),
    manage: ctx.permission("manage", OPERATIONS["lims.manage"]),
    allowed,
    invalid: (message) => fail("LIMS_INVALID", message, "22023"),
    forbidden: (message) => fail("LIMS_FORBIDDEN", message),
    sampleMissing: fail("LIMS_SAMPLE_NOT_FOUND", "no such sample", "P0002"),
    methodMissing: fail(
      "LIMS_METHOD_NOT_FOUND",
      "no such test method",
      "P0002",
    ),
    forms: linked(ctx, "forms"),
    cases: linked(ctx, "cases"),
    assets: linked(ctx, "assets"),
    qualifications: linked(ctx, "qualifications"),
    instrumentQualification:
      typeof qualification === "string" && qualification !== ""
        ? qualification
        : undefined,
    nonconformityKind:
      typeof kind === "string" && kind !== "" ? kind : "nonconformity",
    methodJson: (row) =>
      `jsonb_build_object('id', ${row}.${m("id")}, 'organizationId', ${row}.${m("tenant")}, 'key', ${row}.${m("key")}, 'name', ${row}.${m("name")}, 'unit', ${row}.${m("unit")}, 'lowerLimit', ${row}.${m("lowerLimit")}, 'upperLimit', ${row}.${m("upperLimit")}, 'formId', ${row}.${m("form")}, 'archivedAt', ${row}.${m("archivedAt")}, 'createdAt', ${row}.${m("createdAt")}, 'updatedAt', ${row}.${m("updatedAt")})`,
    sampleJson: (row) =>
      `jsonb_build_object('id', ${row}.${s("id")}, 'organizationId', ${row}.${s("tenant")}, 'number', ${row}.${s("number")}, 'title', ${row}.${s("title")}, 'kind', ${row}.${s("kind")}, 'lot', ${row}.${s("lot")}, 'receivedOn', ${row}.${s("receivedOn")}, 'status', ${row}.${s("status")}, 'notes', ${row}.${s("notes")}, 'rejectionReason', ${row}.${s("rejectionReason")}, 'completedAt', ${row}.${s("completedAt")}, 'releasedAt', ${row}.${s("releasedAt")}, 'createdBy', ${row}.${s("createdBy")}, 'createdAt', ${row}.${s("createdAt")}, 'updatedAt', ${row}.${s("updatedAt")})`,
    resultJson: (row) =>
      `jsonb_build_object('id', ${row}.${r("id")}, 'organizationId', ${row}.${r("tenant")}, 'sampleId', ${row}.${r("sample")}, 'methodId', ${row}.${r("method")}, 'value', ${row}.${r("value")}, 'outcome', ${row}.${r("outcome")}, 'instrumentId', ${row}.${r("instrument")}, 'submissionId', ${row}.${r("submission")}, 'caseId', ${row}.${r("case")}, 'note', ${row}.${r("note")}, 'testedBy', ${row}.${r("testedBy")}, 'testedAt', ${row}.${r("testedAt")}, 'createdAt', ${row}.${r("createdAt")})`,
    recordSample: (type, row, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${s("tenant")}, 'id', ${row}.${s("id")}, 'number', ${row}.${s("number")}, 'status', ${row}.${s("status")})`,
        subject: `'lims-samples/' || ${row}.${s("id")}::text`,
        tenant: `${row}.${s("tenant")}`,
        audit: {
          category: "data",
          targetType: "lims_sample",
          recordId: `${row}.${s("id")}::text`,
          targetLabel: `${row}.${s("number")}`,
          summary: sqlString(summary),
        },
      }),
    recordResult: (type, row, sample, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${r("tenant")}, 'id', ${row}.${r("id")}, 'sampleId', ${row}.${r("sample")}, 'methodId', ${row}.${r("method")}, 'value', ${row}.${r("value")}, 'outcome', ${row}.${r("outcome")}, 'caseId', ${row}.${r("case")})`,
        subject: `'lims-samples/' || ${row}.${r("sample")}::text`,
        tenant: `${row}.${r("tenant")}`,
        audit: {
          category: "data",
          targetType: "lims_sample",
          recordId: `${row}.${r("sample")}::text`,
          targetLabel: `${sample}.${s("number")}`,
          summary: sqlString(summary),
        },
      }),
  };
}
