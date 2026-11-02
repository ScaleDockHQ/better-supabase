import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER } from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";

/** The statuses an OpenVEX statement takes. */
export const ADVISORY_VEX_STATUSES = [
  "not_affected",
  "affected",
  "fixed",
  "under_investigation",
] as const;

/** The justifications OpenVEX allows for `not_affected`. */
export const ADVISORY_VEX_JUSTIFICATIONS = [
  "component_not_present",
  "vulnerable_code_not_present",
  "vulnerable_code_not_in_execute_path",
  "vulnerable_code_cannot_be_controlled_by_adversary",
  "inline_mitigations_already_exist",
] as const;

/** The statuses an advisory moves through. */
export const ADVISORY_SQL_STATUSES = ["draft", "interim", "final"] as const;

/** The ratings a CVSS score maps to. */
export const ADVISORY_SEVERITIES = [
  "none",
  "low",
  "medium",
  "high",
  "critical",
] as const;

export const quoted = (values: readonly string[]): string =>
  values.map((value) => sqlString(value)).join(", ");

/** The SQL pieces the advisories files share. */
export interface AdvisoriesSql {
  readonly ctx: BlockSqlContext;
  readonly fn: (name: string) => string;
  readonly p: (column: string) => string;
  readonly v: (column: string) => string;
  readonly c: (column: string) => string;
  readonly x: (column: string) => string;
  readonly s: (column: string) => string;
  readonly a: (column: string) => string;
  readonly l: (column: string) => string;
  readonly products: string;
  readonly versions: string;
  readonly components: string;
  readonly vulnerabilities: string;
  readonly vex: string;
  readonly advisories: string;
  readonly links: string;
  readonly read: string;
  readonly write: string;
  readonly publish: string;
  readonly allowed: (tenant: string, permission: string) => string;
  readonly invalid: (message: string) => string;
  readonly forbidden: (message: string) => string;
  readonly missing: (what: string) => string;
  readonly productJson: (row: string) => string;
  readonly versionJson: (row: string) => string;
  readonly vulnerabilityJson: (row: string) => string;
  readonly advisoryJson: (row: string) => string;
}

export function advisoriesSql(ctx: BlockSqlContext): AdvisoriesSql {
  const p = (column: string): string => ctx.col("products", column);
  const v = (column: string): string => ctx.col("versions", column);
  const c = (column: string): string => ctx.col("components", column);
  const x = (column: string): string => ctx.col("vulnerabilities", column);
  const s = (column: string): string => ctx.col("vex", column);
  const a = (column: string): string => ctx.col("advisories", column);
  const l = (column: string): string => ctx.col("links", column);

  return {
    ctx,
    fn: (name) => ctx.fn(name),
    p,
    v,
    c,
    x,
    s,
    a,
    l,
    products: ctx.table("products"),
    versions: ctx.table("versions"),
    components: ctx.table("components"),
    vulnerabilities: ctx.table("vulnerabilities"),
    vex: ctx.table("vex"),
    advisories: ctx.table("advisories"),
    links: ctx.table("links"),
    read: ctx.permission("read", OPERATIONS["advisories.read"]),
    write: ctx.permission("write", OPERATIONS["advisories.write"]),
    publish: ctx.permission("publish", OPERATIONS["advisories.publish"]),
    allowed: (tenant, permission) =>
      `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`,
    invalid: (message) => fail("ADVISORY_INVALID", message, "22023"),
    forbidden: (message) => fail("ADVISORY_FORBIDDEN", message),
    missing: (what) =>
      fail(
        "ADVISORY_NOT_FOUND",
        `no such ${what} in this organization`,
        "P0002",
      ),
    productJson: (row) =>
      `jsonb_build_object('id', ${row}.${p("id")}, 'organizationId', ${row}.${p("tenant")}, 'key', ${row}.${p("key")}, 'name', ${row}.${p("name")}, 'vendor', ${row}.${p("vendor")}, 'description', ${row}.${p("description")}, 'archivedAt', ${row}.${p("archivedAt")}, 'createdBy', ${row}.${p("createdBy")}, 'createdAt', ${row}.${p("createdAt")}, 'updatedAt', ${row}.${p("updatedAt")})`,
    versionJson: (row) =>
      `jsonb_build_object('id', ${row}.${v("id")}, 'organizationId', ${row}.${v("tenant")}, 'productId', ${row}.${v("product")}, 'version', ${row}.${v("version")}, 'releasedAt', ${row}.${v("releasedAt")}, 'endOfSupportAt', ${row}.${v("endOfSupportAt")}, 'sbomSerial', ${row}.${v("sbomSerial")}, 'sbomSpec', ${row}.${v("sbomSpec")}, 'sbomComponents', ${row}.${v("sbomComponents")}, 'sbomImportedAt', ${row}.${v("sbomImportedAt")}, 'createdAt', ${row}.${v("createdAt")})`,
    vulnerabilityJson: (row) =>
      `jsonb_build_object('id', ${row}.${x("id")}, 'organizationId', ${row}.${x("tenant")}, 'vulnId', ${row}.${x("vulnId")}, 'aliases', to_jsonb(${row}.${x("aliases")}), 'summary', ${row}.${x("summary")}, 'details', ${row}.${x("details")}, 'cvssVector', ${row}.${x("cvssVector")}, 'cvssVersion', ${row}.${x("cvssVersion")}, 'cvssScore', ${row}.${x("cvssScore")}, 'severity', ${row}.${x("severity")}, 'epssScore', ${row}.${x("epssScore")}, 'epssPercentile', ${row}.${x("epssPercentile")}, 'epssDate', ${row}.${x("epssDate")}, 'kev', ${row}.${x("kev")}, 'kevAddedOn', ${row}.${x("kevAddedOn")}, 'kevDueOn', ${row}.${x("kevDueOn")}, 'kevRansomware', ${row}.${x("kevRansomware")}, 'affectedPurls', to_jsonb(${row}.${x("affectedPurls")}), 'references', ${row}.${x("referenceLinks")}, 'publishedAt', ${row}.${x("publishedAt")}, 'modifiedAt', ${row}.${x("modifiedAt")}, 'enrichedAt', ${row}.${x("enrichedAt")}, 'createdAt', ${row}.${x("createdAt")}, 'updatedAt', ${row}.${x("updatedAt")})`,
    advisoryJson: (row) =>
      `jsonb_build_object('id', ${row}.${a("id")}, 'organizationId', ${row}.${a("tenant")}, 'trackingId', ${row}.${a("trackingId")}, 'title', ${row}.${a("title")}, 'summary', ${row}.${a("summary")}, 'productId', ${row}.${a("product")}, 'severity', ${row}.${a("severity")}, 'status', ${row}.${a("status")}, 'revision', ${row}.${a("revision")}, 'initialReleaseAt', ${row}.${a("initialReleaseAt")}, 'currentReleaseAt', ${row}.${a("currentReleaseAt")}, 'createdBy', ${row}.${a("createdBy")}, 'createdAt', ${row}.${a("createdAt")}, 'updatedAt', ${row}.${a("updatedAt")})`,
  };
}
