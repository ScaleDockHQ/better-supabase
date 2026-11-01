import type { AdvisoriesEvents } from "../../blocks/advisories/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { entityType } from "../resolved-names.ts";
import { lockTable, schemaPreamble } from "../shared.ts";
import { advisoriesFunctions } from "./advisories-functions.ts";
import {
  ADVISORY_SEVERITIES,
  ADVISORY_SQL_STATUSES,
  ADVISORY_VEX_JUSTIFICATIONS,
  ADVISORY_VEX_STATUSES,
  advisoriesSql,
  quoted,
} from "./advisories-sql.ts";

const product = {
  subject: "advisory-products",
  payload: ["organizationId", "id", "key", "name"],
} as const;

const vulnerability = {
  subject: "vulnerabilities",
  payload: [
    "organizationId",
    "id",
    "vulnId",
    "severity",
    "cvssScore",
    "epssScore",
    "kev",
  ],
} as const;

const advisory = {
  subject: "advisories",
  payload: [
    "organizationId",
    "id",
    "trackingId",
    "title",
    "status",
    "revision",
  ],
} as const;

const EVENTS: BlockSqlEvents<AdvisoriesEvents> = {
  "advisory_product.created": product,
  "advisory_product.updated": product,
  "advisory_product_version.created": {
    subject: "advisory-product-versions",
    payload: ["organizationId", "id", "productId", "version"],
  },
  "sbom_component.imported": {
    subject: "advisory-product-versions",
    payload: [
      "organizationId",
      "versionId",
      "productId",
      "componentCount",
      "serialNumber",
    ],
  },
  "vulnerability.created": vulnerability,
  "vulnerability.enriched": vulnerability,
  "vulnerability.exploited": {
    subject: "vulnerabilities",
    payload: [...vulnerability.payload, "kevAddedOn", "kevDueOn"],
  },
  "vex_statement.saved": {
    subject: "vex-statements",
    payload: [
      "organizationId",
      "id",
      "productId",
      "versionId",
      "vulnerabilityId",
      "vulnId",
      "status",
    ],
  },
  "advisory.created": advisory,
  "advisory.updated": advisory,
  "advisory.published": advisory,
};

const NAMES: BlockSqlNames = {
  entities: {
    advisory: {
      table: "advisories",
      singular: "advisory",
      plural: "advisories",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "write" },
        search: { title: "title", body: ["trackingId", "summary"] },
      },
    },
    advisory_product: {
      table: "products",
      singular: "advisory_product",
      subject: {
        title: "name",
        deletedAt: "archivedAt",
        permissions: { read: "read", write: "write" },
      },
    },
    advisory_product_version: {
      table: "versions",
      singular: "advisory_product_version",
    },
    sbom_component: { table: "components", singular: "sbom_component" },
    vulnerability: {
      table: "vulnerabilities",
      singular: "vulnerability",
      plural: "vulnerabilities",
      subject: {
        title: "vulnId",
        permissions: { read: "read", write: "write" },
        search: { title: "vulnId", body: ["summary"] },
      },
    },
    vex_statement: { table: "vex", singular: "vex_statement" },
    advisory_vulnerability: {
      table: "links",
      singular: "advisory_vulnerability",
    },
  },
  events: EVENTS,
  hooks: [],
  options: [],
  tables: {
    products: {
      name: "advisory_products",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        key: "key",
        name: "name",
        vendor: "vendor",
        description: "description",
        archivedAt: "archived_at",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    versions: {
      name: "advisory_product_versions",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        product: "product_id",
        version: "version",
        releasedAt: "released_at",
        endOfSupportAt: "end_of_support_at",
        sbomSerial: "sbom_serial",
        sbomSpec: "sbom_spec",
        sbomComponents: "sbom_component_count",
        sbomImportedAt: "sbom_imported_at",
        createdAt: "created_at",
      },
    },
    components: {
      name: "sbom_components",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        version: "version_id",
        bomRef: "bom_ref",
        kind: "component_type",
        name: "name",
        componentVersion: "component_version",
        purl: "purl",
        packagePurl: "package_purl",
        cpe: "cpe",
        supplier: "supplier",
        licenses: "licenses",
        hashes: "hashes",
      },
    },
    vulnerabilities: {
      name: "vulnerabilities",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        vulnId: "vuln_id",
        aliases: "aliases",
        summary: "summary",
        details: "details",
        cvssVector: "cvss_vector",
        cvssVersion: "cvss_version",
        cvssScore: "cvss_score",
        severity: "severity",
        epssScore: "epss_score",
        epssPercentile: "epss_percentile",
        epssDate: "epss_date",
        kev: "kev",
        kevAddedOn: "kev_added_on",
        kevDueOn: "kev_due_on",
        kevRansomware: "kev_ransomware",
        affectedPurls: "affected_purls",
        referenceLinks: "reference_links",
        publishedAt: "published_at",
        modifiedAt: "modified_at",
        enrichedAt: "enriched_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    vex: {
      name: "vex_statements",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        product: "product_id",
        version: "version_id",
        vulnerability: "vulnerability_id",
        status: "status",
        justification: "justification",
        impactStatement: "impact_statement",
        actionStatement: "action_statement",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    advisories: {
      name: "advisories",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        trackingId: "tracking_id",
        title: "title",
        summary: "summary",
        product: "product_id",
        severity: "severity",
        status: "status",
        revision: "revision",
        initialReleaseAt: "initial_release_at",
        currentReleaseAt: "current_release_at",
        revisionHistory: "revision_history",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    links: {
      name: "advisory_vulnerabilities",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        tenant: "tenant_id",
        advisory: "advisory_id",
        vulnerability: "vulnerability_id",
        createdAt: "created_at",
      },
    },
  },
};

function tables(ctx: BlockSqlContext): string {
  const q = advisoriesSql(ctx);
  const { p, v, c, x, s, a, l } = q;

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const readPolicy = (logical: string, tenant: string): string =>
    renderPolicy(
      makePolicy({
        table: ctx.table(logical),
        name: ctx.owns(logical)
          ? name(logical, "read")
          : sqlIdent(`bsb_${ctx.tableName(logical).name}_read`),
        command: "select",
        roles: ["authenticated"],
        using: ctx.scope.check(tenant, q.read),
      }),
      { drop: true, target: ctx.table(logical) },
    );

  const guard = (logical: string, tenant: string): string =>
    `${lockTable(ctx.table(logical), { read: true })}
${readPolicy(logical, tenant)}`;

  return `
create table if not exists ${q.products} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  -- Names the product in OpenVEX and CSAF documents.
  ${p("key")} text not null check (${p("key")} ~ '^[a-z0-9][a-z0-9._-]{0,62}$'),
  ${p("name")} text not null check (length(${p("name")}) between 1 and 200),
  ${p("vendor")} text check (${p("vendor")} is null or length(${p("vendor")}) <= 200),
  ${p("description")} text check (${p("description")} is null or length(${p("description")}) <= 5000),
  ${p("archivedAt")} timestamptz,
  ${p("createdBy")} uuid,
  ${p("createdAt")} timestamptz not null default now(),
  ${p("updatedAt")} timestamptz not null default now()
);
create unique index if not exists ${name("products", "key_idx")} on ${q.products} (${p("tenant")}, ${p("key")});
${guard("products", p("tenant"))}

create table if not exists ${q.versions} (
  ${v("id")} uuid primary key default gen_random_uuid(),
  ${v("tenant")} ${ctx.idType} not null,
  ${v("product")} uuid not null,
  ${v("version")} text not null check (length(${v("version")}) between 1 and 100),
  ${v("releasedAt")} timestamptz,
  ${v("endOfSupportAt")} timestamptz,
  -- The BOM the components came from: its urn:uuid serial and CycloneDX version.
  ${v("sbomSerial")} text,
  ${v("sbomSpec")} text,
  ${v("sbomComponents")} integer not null default 0,
  ${v("sbomImportedAt")} timestamptz,
  ${v("createdAt")} timestamptz not null default now()
);
create unique index if not exists ${name("versions", "product_idx")} on ${q.versions} (${v("tenant")}, ${v("product")}, ${v("version")});
${guard("versions", v("tenant"))}

create table if not exists ${q.components} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("version")} uuid not null,
  ${c("bomRef")} text,
  ${c("kind")} text not null default 'library',
  ${c("name")} text not null check (length(${c("name")}) between 1 and 500),
  ${c("componentVersion")} text,
  ${c("purl")} text,
  -- The purl without version, qualifiers and subpath, which vulnerabilities match on.
  ${c("packagePurl")} text,
  ${c("cpe")} text,
  ${c("supplier")} text,
  ${c("licenses")} text[] not null default '{}',
  ${c("hashes")} jsonb not null default '[]'
);
create index if not exists ${name("components", "version_idx")} on ${q.components} (${c("tenant")}, ${c("version")});
create index if not exists ${name("components", "package_idx")} on ${q.components} (${c("tenant")}, ${c("packagePurl")}) where ${c("packagePurl")} is not null;
${guard("components", c("tenant"))}

create table if not exists ${q.vulnerabilities} (
  ${x("id")} uuid primary key default gen_random_uuid(),
  ${x("tenant")} ${ctx.idType} not null,
  ${x("vulnId")} text not null check (${x("vulnId")} ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{2,127}$'),
  ${x("aliases")} text[] not null default '{}',
  ${x("summary")} text check (${x("summary")} is null or length(${x("summary")}) <= 1000),
  ${x("details")} text check (${x("details")} is null or length(${x("details")}) <= 20000),
  ${x("cvssVector")} text check (${x("cvssVector")} is null or length(${x("cvssVector")}) <= 300),
  ${x("cvssVersion")} text check (${x("cvssVersion")} is null or ${x("cvssVersion")} in ('3.0', '3.1', '4.0')),
  ${x("cvssScore")} numeric(3, 1) check (${x("cvssScore")} is null or ${x("cvssScore")} between 0 and 10),
  ${x("severity")} text check (${x("severity")} is null or ${x("severity")} in (${quoted(ADVISORY_SEVERITIES)})),
  ${x("epssScore")} numeric(6, 5) check (${x("epssScore")} is null or ${x("epssScore")} between 0 and 1),
  ${x("epssPercentile")} numeric(6, 5) check (${x("epssPercentile")} is null or ${x("epssPercentile")} between 0 and 1),
  ${x("epssDate")} date,
  ${x("kev")} boolean not null default false,
  ${x("kevAddedOn")} date,
  ${x("kevDueOn")} date,
  ${x("kevRansomware")} boolean not null default false,
  -- Package URLs without a version, from OSV; exposure matches components on them.
  ${x("affectedPurls")} text[] not null default '{}',
  ${x("referenceLinks")} jsonb not null default '[]',
  ${x("publishedAt")} timestamptz,
  ${x("modifiedAt")} timestamptz,
  ${x("enrichedAt")} timestamptz,
  ${x("createdAt")} timestamptz not null default now(),
  ${x("updatedAt")} timestamptz not null default now()
);
create unique index if not exists ${name("vulnerabilities", "vuln_idx")} on ${q.vulnerabilities} (${x("tenant")}, ${x("vulnId")});
create index if not exists ${name("vulnerabilities", "purls_idx")} on ${q.vulnerabilities} using gin (${x("affectedPurls")});
create index if not exists ${name("vulnerabilities", "due_idx")} on ${q.vulnerabilities} (${x("enrichedAt")} nulls first);
${guard("vulnerabilities", x("tenant"))}

create table if not exists ${q.vex} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${ctx.idType} not null,
  ${s("product")} uuid not null,
  -- Null: the statement covers every version of the product.
  ${s("version")} uuid,
  ${s("vulnerability")} uuid not null,
  ${s("status")} text not null check (${s("status")} in (${quoted(ADVISORY_VEX_STATUSES)})),
  ${s("justification")} text check (${s("justification")} is null or ${s("justification")} in (${quoted(ADVISORY_VEX_JUSTIFICATIONS)})),
  ${s("impactStatement")} text check (${s("impactStatement")} is null or length(${s("impactStatement")}) <= 5000),
  ${s("actionStatement")} text check (${s("actionStatement")} is null or length(${s("actionStatement")}) <= 5000),
  ${s("createdBy")} uuid,
  ${s("createdAt")} timestamptz not null default now(),
  ${s("updatedAt")} timestamptz not null default now()
);
create unique index if not exists ${name("vex", "scope_idx")} on ${q.vex} (${s("tenant")}, ${s("product")}, ${s("vulnerability")}, coalesce(${s("version")}, '00000000-0000-0000-0000-000000000000'::uuid));
${guard("vex", s("tenant"))}

create table if not exists ${q.advisories} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.idType} not null,
  -- The CSAF tracking id, such as ACME-SA-2026-001.
  ${a("trackingId")} text not null check (${a("trackingId")} ~ '^[A-Za-z0-9][A-Za-z0-9._-]{2,99}$'),
  ${a("title")} text not null check (length(${a("title")}) between 1 and 300),
  ${a("summary")} text check (${a("summary")} is null or length(${a("summary")}) <= 10000),
  ${a("product")} uuid not null,
  ${a("severity")} text check (${a("severity")} is null or ${a("severity")} in (${quoted(ADVISORY_SEVERITIES)})),
  ${a("status")} text not null default 'draft' check (${a("status")} in (${quoted(ADVISORY_SQL_STATUSES)})),
  -- The CSAF document version: 0 for a draft, then one more per publication.
  ${a("revision")} integer not null default 0 check (${a("revision")} >= 0),
  ${a("initialReleaseAt")} timestamptz,
  ${a("currentReleaseAt")} timestamptz,
  -- [{ number, date, summary }], one entry per publication.
  ${a("revisionHistory")} jsonb not null default '[]' check (jsonb_typeof(${a("revisionHistory")}) = 'array'),
  ${a("createdBy")} uuid,
  ${a("createdAt")} timestamptz not null default now(),
  ${a("updatedAt")} timestamptz not null default now()
);
create unique index if not exists ${name("advisories", "tracking_idx")} on ${q.advisories} (${a("tenant")}, ${a("trackingId")});
create index if not exists ${name("advisories", "status_idx")} on ${q.advisories} (${a("tenant")}, ${a("status")}, ${a("createdAt")} desc);
${guard("advisories", a("tenant"))}

create table if not exists ${q.links} (
  ${l("tenant")} ${ctx.idType} not null,
  ${l("advisory")} uuid not null,
  ${l("vulnerability")} uuid not null,
  ${l("createdAt")} timestamptz not null default now(),
  primary key (${l("advisory")}, ${l("vulnerability")})
);
create index if not exists ${name("links", "vuln_idx")} on ${q.links} (${l("tenant")}, ${l("vulnerability")});
${guard("links", l("tenant"))}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Security advisories for a software vendor: products and versions with their
-- CycloneDX components, vulnerabilities enriched from OSV, EPSS and the CISA KEV
-- catalog, OpenVEX statements per version and CSAF 2.0 advisories.
${tables(ctx)}
${advisoriesFunctions(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "list_advisory_products", args: ["{id}"], returns: "jsonb" },
    {
      name: "save_advisory_product",
      args: ["{id}", "text", "text", "text", "text", "boolean", "uuid"],
      returns: "jsonb",
    },
    {
      name: "create_product_version",
      args: ["{id}", "uuid", "text", "timestamptz", "timestamptz"],
      returns: "jsonb",
    },
    { name: "list_product_versions", args: ["{id}", "uuid"], returns: "jsonb" },
    {
      name: "import_sbom",
      args: ["{id}", "uuid", "jsonb", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "list_sbom_components",
      args: ["{id}", "uuid", "integer"],
      returns: "jsonb",
    },
    {
      name: "save_vulnerability",
      args: [
        "{id}",
        "text",
        "text",
        "text",
        "text[]",
        "text",
        "text",
        "numeric",
        "text[]",
      ],
      returns: "jsonb",
    },
    {
      name: "record_vulnerability_enrichment",
      args: ["{id}", "text", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "vulnerabilities_due",
      args: ["{id}", "integer", "interval"],
      returns: "jsonb",
    },
    {
      name: "list_vulnerabilities",
      args: ["{id}", "boolean", "integer"],
      returns: "jsonb",
    },
    { name: "version_exposure", args: ["{id}", "uuid"], returns: "jsonb" },
    {
      name: "save_vex_statement",
      args: ["{id}", "uuid", "uuid", "text", "uuid", "text", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "list_vex_statements",
      args: ["{id}", "uuid", "uuid"],
      returns: "jsonb",
    },
    {
      name: "save_advisory",
      args: ["{id}", "text", "text", "text", "uuid", "uuid[]", "text", "uuid"],
      returns: "jsonb",
    },
    {
      name: "publish_advisory",
      args: ["{id}", "uuid", "text", "text"],
      returns: "jsonb",
    },
    { name: "list_advisories", args: ["{id}", "text"], returns: "jsonb" },
    { name: "get_advisory", args: ["{id}", "uuid"], returns: "jsonb" },
    {
      name: "get_published_advisory",
      args: ["{id}", "text"],
      returns: "jsonb",
    },
    { name: "list_published_advisories", args: ["{id}"], returns: "jsonb" },
  ];
}

/** A subject type of another block, after its renames when it's installed. */
const typeOf = (
  own: BlockSqlContext,
  module: string,
  entity: string,
): string =>
  own.installed(module) ? entityType(own.of(module).resolved, entity) : entity;

const CONTRIBUTES: BlockContributes = {
  relations: (own) => [
    ...(own.installed("incidents")
      ? [
          {
            kind: "reported_as",
            inverse: "reports",
            types: {
              source: [own.naming.rename("vulnerability")],
              // The CRA reporting of an actively exploited vulnerability.
              target: [typeOf(own, "incidents", "incident")],
            },
          },
        ]
      : []),
    ...(own.installed("risks")
      ? [
          {
            kind: "tracked_as",
            inverse: "tracks",
            types: {
              source: [
                own.naming.rename("vulnerability"),
                own.naming.rename("advisory"),
              ],
              target: [typeOf(own, "risks", "risk")],
            },
          },
        ]
      : []),
  ],
};

export const ADVISORIES: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  name: "advisories",
  scopes: ["tenant"],
  title: "Security advisories",
  description:
    "Security advisories for a software vendor: products and versions with CycloneDX components, vulnerabilities enriched from OSV, EPSS and the CISA KEV catalog on a schedule, OpenVEX statements per version, and CSAF 2.0 advisories with a /.well-known/csaf handler, linked to incidents and risks through relations.",
  requires: ["memberships", "permissions", "subjects"],
  integrates: ["relations", "incidents", "risks", "outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
