import type { BlockSqlContext } from "../context.ts";
import type { AdvisoriesSql } from "./advisories-sql.ts";

import { sqlString } from "../../core/template.ts";
import { fail, pageSize, serviceGrant, userGrant } from "../shared.ts";
import {
  ADVISORY_SEVERITIES,
  ADVISORY_VEX_JUSTIFICATIONS,
  ADVISORY_VEX_STATUSES,
  advisoriesSql,
  quoted,
} from "./advisories-sql.ts";

const HEADER = `returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable`;

/** The records every mutating function emits, so the payloads stay uniform. */
function recorders(q: AdvisoriesSql): {
  readonly product: (type: string, row: string, summary: string) => string;
  readonly version: (type: string, row: string, summary: string) => string;
  readonly vulnerability: (
    type: string,
    row: string,
    summary: string | false,
    extra?: string,
  ) => string;
  readonly statement: (type: string, row: string, vulnId: string) => string;
  readonly advisory: (type: string, row: string, summary: string) => string;
} {
  const { ctx, p, v, x, s, a } = q;

  return {
    product: (type, row, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${p("tenant")}, 'id', ${row}.${p("id")}, 'key', ${row}.${p("key")}, 'name', ${row}.${p("name")})`,
        subject: `'advisory-products/' || ${row}.${p("id")}::text`,
        tenant: `${row}.${p("tenant")}`,
        audit: {
          category: "data",
          targetType: "advisory_product",
          recordId: `${row}.${p("id")}::text`,
          targetLabel: `${row}.${p("name")}`,
          summary: sqlString(summary),
        },
      }),
    version: (type, row, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${v("tenant")}, 'id', ${row}.${v("id")}, 'productId', ${row}.${v("product")}, 'version', ${row}.${v("version")})`,
        subject: `'advisory-product-versions/' || ${row}.${v("id")}::text`,
        tenant: `${row}.${v("tenant")}`,
        audit: {
          category: "data",
          targetType: "advisory_product_version",
          recordId: `${row}.${v("id")}::text`,
          targetLabel: `${row}.${v("version")}`,
          summary: sqlString(summary),
        },
      }),
    vulnerability: (type, row, summary, extra = "") =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${x("tenant")}, 'id', ${row}.${x("id")}, 'vulnId', ${row}.${x("vulnId")}, 'severity', ${row}.${x("severity")}, 'cvssScore', ${row}.${x("cvssScore")}, 'epssScore', ${row}.${x("epssScore")}, 'kev', ${row}.${x("kev")}${extra})`,
        subject: `'vulnerabilities/' || ${row}.${x("id")}::text`,
        tenant: `${row}.${x("tenant")}`,
        audit:
          summary === false
            ? false
            : {
                category: "data",
                targetType: "vulnerability",
                recordId: `${row}.${x("id")}::text`,
                targetLabel: `${row}.${x("vulnId")}`,
                summary: sqlString(summary),
              },
      }),
    statement: (type, row, vulnId) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${s("tenant")}, 'id', ${row}.${s("id")}, 'productId', ${row}.${s("product")}, 'versionId', ${row}.${s("version")}, 'vulnerabilityId', ${row}.${s("vulnerability")}, 'vulnId', ${vulnId}, 'status', ${row}.${s("status")})`,
        subject: `'vex-statements/' || ${row}.${s("id")}::text`,
        tenant: `${row}.${s("tenant")}`,
        audit: {
          category: "data",
          targetType: "vex_statement",
          recordId: `${row}.${s("id")}::text`,
          targetLabel: vulnId,
          summary: sqlString("VEX statement saved"),
        },
      }),
    advisory: (type, row, summary) =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${a("tenant")}, 'id', ${row}.${a("id")}, 'trackingId', ${row}.${a("trackingId")}, 'title', ${row}.${a("title")}, 'status', ${row}.${a("status")}, 'revision', ${row}.${a("revision")})`,
        subject: `'advisories/' || ${row}.${a("id")}::text`,
        tenant: `${row}.${a("tenant")}`,
        audit: {
          category: "data",
          targetType: "advisory",
          recordId: `${row}.${a("id")}::text`,
          targetLabel: `${row}.${a("trackingId")}`,
          summary: sqlString(summary),
        },
      }),
  };
}

function productFunctions(
  q: AdvisoriesSql,
  ctx: BlockSqlContext,
  rec: ReturnType<typeof recorders>,
): string {
  const { fn, p, v, products, versions, productJson, versionJson } = q;
  const idType = ctx.idType;

  return `
-- The organization's products, the newest first.
create or replace function ${fn("list_advisory_products")}(tenant ${idType})
${HEADER}
begin
  if not ${q.allowed("list_advisory_products.tenant", q.read)} then
    ${q.forbidden("not allowed to read advisories")}
  end if;
  return coalesce((
    select jsonb_agg(${productJson("y")} order by y.${p("createdAt")} desc)
    from ${products} y where y.${p("tenant")} = list_advisory_products.tenant
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_advisory_products")}(${idType})`)}

-- Creates a product or, with product_id, changes one. The key is lowercase
-- letters, digits, dots, dashes and underscores; it names the product in OpenVEX
-- and CSAF documents. archived true takes the product off the lists.
create or replace function ${fn("save_advisory_product")}(tenant ${idType}, key text, name text, vendor text default null, description text default null, archived boolean default null, product_id uuid default null)
${HEADER}
declare
  v_row ${products};
  v_old ${products};
begin
  if not ${q.allowed("save_advisory_product.tenant", q.write)} then
    ${q.forbidden("not allowed to change advisories")}
  end if;
  if coalesce(save_advisory_product.key, '') !~ '^[a-z0-9][a-z0-9._-]{0,62}$' then
    ${q.invalid("key must be lowercase letters, digits, dots, dashes and underscores, 1 to 63 characters")}
  end if;
  if coalesce(length(trim(save_advisory_product.name)), 0) not between 1 and 200 then
    ${q.invalid("name must be 1 to 200 characters")}
  end if;
  if length(save_advisory_product.vendor) > 200 or length(save_advisory_product.description) > 5000 then
    ${q.invalid("vendor is at most 200 characters and description at most 5000")}
  end if;
  if save_advisory_product.product_id is not null then
    select * into v_old from ${products} y
    where y.${p("id")} = save_advisory_product.product_id and y.${p("tenant")} = save_advisory_product.tenant
    for update;
    if not found then
      ${q.missing("product")}
    end if;
  end if;
  if v_old.${p("id")} is null then
    insert into ${products} (${p("tenant")}, ${p("key")}, ${p("name")}, ${p("vendor")}, ${p("description")}, ${p("createdBy")})
    values (save_advisory_product.tenant, save_advisory_product.key, trim(save_advisory_product.name), nullif(trim(save_advisory_product.vendor), ''), nullif(trim(save_advisory_product.description), ''), (select auth.uid()))
    returning * into v_row;
    ${rec.product("advisory_product.created", "v_row", "advisory product created")}
  else
    update ${products} y set
      ${p("key")} = save_advisory_product.key,
      ${p("name")} = trim(save_advisory_product.name),
      ${p("vendor")} = nullif(trim(save_advisory_product.vendor), ''),
      ${p("description")} = nullif(trim(save_advisory_product.description), ''),
      ${p("archivedAt")} = case
        when save_advisory_product.archived is null then y.${p("archivedAt")}
        when save_advisory_product.archived then coalesce(y.${p("archivedAt")}, now())
        else null end,
      ${p("updatedAt")} = now()
    where y.${p("id")} = v_old.${p("id")}
    returning * into v_row;
    ${rec.product("advisory_product.updated", "v_row", "advisory product updated")}
  end if;
  return ${productJson("v_row")};
exception when unique_violation then
  ${q.invalid("another product of this organization has this key")}
end;
$$;
${userGrant(`${fn("save_advisory_product")}(${idType}, text, text, text, text, boolean, uuid)`)}

-- Adds a version to a product. Versions are free text, such as 2.4.1.
create or replace function ${fn("create_product_version")}(tenant ${idType}, product_id uuid, version text, released_at timestamptz default null, end_of_support_at timestamptz default null)
${HEADER}
declare
  v_row ${versions};
begin
  if not ${q.allowed("create_product_version.tenant", q.write)} then
    ${q.forbidden("not allowed to change advisories")}
  end if;
  if coalesce(length(trim(create_product_version.version)), 0) not between 1 and 100 then
    ${q.invalid("version must be 1 to 100 characters")}
  end if;
  if not exists (
    select 1 from ${products} y
    where y.${p("id")} = create_product_version.product_id and y.${p("tenant")} = create_product_version.tenant
  ) then
    ${q.missing("product")}
  end if;
  insert into ${versions} (${v("tenant")}, ${v("product")}, ${v("version")}, ${v("releasedAt")}, ${v("endOfSupportAt")})
  values (create_product_version.tenant, create_product_version.product_id, trim(create_product_version.version), create_product_version.released_at, create_product_version.end_of_support_at)
  returning * into v_row;
  ${rec.version("advisory_product_version.created", "v_row", "product version created")}
  return ${versionJson("v_row")};
exception when unique_violation then
  ${q.invalid("this product already has this version")}
end;
$$;
${userGrant(`${fn("create_product_version")}(${idType}, uuid, text, timestamptz, timestamptz)`)}

-- The versions of a product, the newest first.
create or replace function ${fn("list_product_versions")}(tenant ${idType}, product_id uuid)
${HEADER}
begin
  if not ${q.allowed("list_product_versions.tenant", q.read)} then
    ${q.forbidden("not allowed to read advisories")}
  end if;
  return coalesce((
    select jsonb_agg(${versionJson("y")} order by y.${v("createdAt")} desc, y.${v("version")})
    from ${versions} y
    where y.${v("tenant")} = list_product_versions.tenant and y.${v("product")} = list_product_versions.product_id
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_product_versions")}(${idType}, uuid)`)}
`;
}

function sbomFunctions(q: AdvisoriesSql, ctx: BlockSqlContext): string {
  const { fn, v, c, versions, components } = q;
  const idType = ctx.idType;

  const bad = q.invalid(
    "components must be a list of at most 20000 components, each with a name",
  );

  return `
-- Replaces the components of a version with a parsed CycloneDX BOM. components
-- is [{ bomRef, type, name, version, purl, cpe, supplier, licenses, hashes }];
-- the TypeScript client parses the document, this function validates and stores
-- the result. package_purl is the purl without version, qualifiers and subpath,
-- the key vulnerabilities match on.
create or replace function ${fn("import_sbom")}(tenant ${idType}, version_id uuid, components jsonb, serial_number text default null, spec_version text default null)
${HEADER}
declare
  v_row ${versions};
  v_count integer;
begin
  if not ${q.allowed("import_sbom.tenant", q.write)} then
    ${q.forbidden("not allowed to change advisories")}
  end if;
  if jsonb_typeof(import_sbom.components) is distinct from 'array' or jsonb_array_length(import_sbom.components) > 20000 then
    ${bad}
  end if;
  if exists (
    select 1 from jsonb_array_elements(import_sbom.components) e
    where jsonb_typeof(e) <> 'object' or coalesce(length(trim(e ->> 'name')), 0) not between 1 and 500
      or length(e ->> 'purl') > 2000 or length(e ->> 'version') > 200
      or (e ? 'licenses' and jsonb_typeof(e -> 'licenses') <> 'array')
      or (e ? 'hashes' and jsonb_typeof(e -> 'hashes') <> 'array')
  ) then
    ${bad}
  end if;
  select * into v_row from ${versions} y
  where y.${v("id")} = import_sbom.version_id and y.${v("tenant")} = import_sbom.tenant
  for update;
  if not found then
    ${q.missing("product version")}
  end if;
  delete from ${components} z where z.${c("tenant")} = import_sbom.tenant and z.${c("version")} = import_sbom.version_id;
  insert into ${components} (${c("tenant")}, ${c("version")}, ${c("bomRef")}, ${c("kind")}, ${c("name")}, ${c("componentVersion")}, ${c("purl")}, ${c("packagePurl")}, ${c("cpe")}, ${c("supplier")}, ${c("licenses")}, ${c("hashes")})
  select import_sbom.tenant, import_sbom.version_id,
    nullif(e ->> 'bomRef', ''), coalesce(nullif(e ->> 'type', ''), 'library'), trim(e ->> 'name'),
    nullif(e ->> 'version', ''), nullif(e ->> 'purl', ''),
    case when nullif(e ->> 'purl', '') is null then null
      else regexp_replace(regexp_replace(e ->> 'purl', '[?#].*$', ''), '@[^@/]*$', '') end,
    nullif(e ->> 'cpe', ''), nullif(e ->> 'supplier', ''),
    case when jsonb_typeof(e -> 'licenses') = 'array' then array(select jsonb_array_elements_text(e -> 'licenses')) else '{}'::text[] end,
    case when jsonb_typeof(e -> 'hashes') = 'array' then e -> 'hashes' else '[]'::jsonb end
  from jsonb_array_elements(import_sbom.components) e;
  get diagnostics v_count = row_count;
  update ${versions} y set
    ${v("sbomSerial")} = nullif(import_sbom.serial_number, ''),
    ${v("sbomSpec")} = nullif(import_sbom.spec_version, ''),
    ${v("sbomComponents")} = v_count,
    ${v("sbomImportedAt")} = now()
  where y.${v("id")} = v_row.${v("id")}
  returning * into v_row;
  ${ctx.record({
    type: "sbom_component.imported",
    payload: `jsonb_build_object('organizationId', v_row.${v("tenant")}, 'versionId', v_row.${v("id")}, 'productId', v_row.${v("product")}, 'componentCount', v_count, 'serialNumber', v_row.${v("sbomSerial")})`,
    subject: `'advisory-product-versions/' || v_row.${v("id")}::text`,
    tenant: `v_row.${v("tenant")}`,
    audit: {
      category: "data",
      targetType: "advisory_product_version",
      recordId: `v_row.${v("id")}::text`,
      targetLabel: `v_row.${v("version")}`,
      summary: sqlString("SBOM imported"),
    },
  })}
  return ${q.versionJson("v_row")};
end;
$$;
${userGrant(`${fn("import_sbom")}(${idType}, uuid, jsonb, text, text)`)}

-- The components of a version by name.
create or replace function ${fn("list_sbom_components")}(tenant ${idType}, version_id uuid, max_count integer default null)
${HEADER}
begin
  if not ${q.allowed("list_sbom_components.tenant", q.read)} then
    ${q.forbidden("not allowed to read advisories")}
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t.${c("id")}, 'bomRef', t.${c("bomRef")}, 'type', t.${c("kind")}, 'name', t.${c("name")}, 'version', t.${c("componentVersion")}, 'purl', t.${c("purl")}, 'cpe', t.${c("cpe")}, 'supplier', t.${c("supplier")}, 'licenses', to_jsonb(t.${c("licenses")}), 'hashes', t.${c("hashes")}) order by t.${c("name")}, t.${c("componentVersion")})
    from (
      select z.* from ${components} z
      where z.${c("tenant")} = list_sbom_components.tenant and z.${c("version")} = list_sbom_components.version_id
      order by z.${c("name")}, z.${c("componentVersion")}
      limit ${pageSize("list_sbom_components.max_count", 1000, 5000)}
    ) t
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_sbom_components")}(${idType}, uuid, integer)`)}
`;
}

function vulnerabilityFunctions(
  q: AdvisoriesSql,
  ctx: BlockSqlContext,
  rec: ReturnType<typeof recorders>,
): string {
  const { fn, x, vulnerabilities, vulnerabilityJson } = q;
  const idType = ctx.idType;

  const ID = (arg: string): string =>
    `case when upper(trim(${arg})) like 'CVE-%' then upper(trim(${arg})) else trim(${arg}) end`;

  return `
-- Registers a vulnerability the organization tracks, or changes what a person
-- entered. A null argument keeps the stored value. cvss_version is 3.0, 3.1 or
-- 4.0; the TypeScript client parses the vector and passes the version and score.
create or replace function ${fn("save_vulnerability")}(tenant ${idType}, vuln_id text, summary text default null, details text default null, aliases text[] default null, cvss_vector text default null, cvss_version text default null, cvss_score numeric default null, affected_purls text[] default null)
${HEADER}
declare
  v_row ${vulnerabilities};
  v_old ${vulnerabilities};
  v_id text := ${ID("save_vulnerability.vuln_id")};
begin
  if not ${q.allowed("save_vulnerability.tenant", q.write)} then
    ${q.forbidden("not allowed to change advisories")}
  end if;
  if coalesce(v_id, '') !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{2,127}$' then
    ${q.invalid("vuln_id must be a CVE, GHSA or other vulnerability id of 3 to 128 characters")}
  end if;
  if length(save_vulnerability.summary) > 1000 or length(save_vulnerability.details) > 20000 or length(save_vulnerability.cvss_vector) > 300 then
    ${q.invalid("summary is at most 1000 characters, details 20000 and the CVSS vector 300")}
  end if;
  if save_vulnerability.cvss_version is not null and save_vulnerability.cvss_version not in ('3.0', '3.1', '4.0') then
    ${q.invalid("cvss_version must be 3.0, 3.1 or 4.0")}
  end if;
  if save_vulnerability.cvss_score is not null and save_vulnerability.cvss_score not between 0 and 10 then
    ${q.invalid("cvss_score must be between 0 and 10")}
  end if;
  select * into v_old from ${vulnerabilities} y
  where y.${x("tenant")} = save_vulnerability.tenant and y.${x("vulnId")} = v_id
  for update;
  if v_old.${x("id")} is null then
    insert into ${vulnerabilities} (${x("tenant")}, ${x("vulnId")}, ${x("summary")}, ${x("details")}, ${x("aliases")}, ${x("cvssVector")}, ${x("cvssVersion")}, ${x("cvssScore")}, ${x("severity")}, ${x("affectedPurls")})
    values (save_vulnerability.tenant, v_id, nullif(trim(save_vulnerability.summary), ''), nullif(trim(save_vulnerability.details), ''),
      coalesce(save_vulnerability.aliases, '{}'::text[]), save_vulnerability.cvss_vector, save_vulnerability.cvss_version, save_vulnerability.cvss_score,
      ${severityOf("save_vulnerability.cvss_score")}, coalesce(save_vulnerability.affected_purls, '{}'::text[]))
    returning * into v_row;
    ${rec.vulnerability("vulnerability.created", "v_row", "vulnerability registered")}
  else
    update ${vulnerabilities} y set
      ${x("summary")} = coalesce(nullif(trim(save_vulnerability.summary), ''), y.${x("summary")}),
      ${x("details")} = coalesce(nullif(trim(save_vulnerability.details), ''), y.${x("details")}),
      ${x("aliases")} = coalesce(save_vulnerability.aliases, y.${x("aliases")}),
      ${x("cvssVector")} = coalesce(save_vulnerability.cvss_vector, y.${x("cvssVector")}),
      ${x("cvssVersion")} = coalesce(save_vulnerability.cvss_version, y.${x("cvssVersion")}),
      ${x("cvssScore")} = coalesce(save_vulnerability.cvss_score, y.${x("cvssScore")}),
      ${x("severity")} = coalesce(${severityOf("save_vulnerability.cvss_score")}, y.${x("severity")}),
      ${x("affectedPurls")} = coalesce(save_vulnerability.affected_purls, y.${x("affectedPurls")}),
      ${x("updatedAt")} = now()
    where y.${x("id")} = v_old.${x("id")}
    returning * into v_row;
  end if;
  return ${vulnerabilityJson("v_row")};
end;
$$;
${userGrant(`${fn("save_vulnerability")}(${idType}, text, text, text, text[], text, text, numeric, text[])`)}

-- Stores what the vulnerability feed found for a tracked vulnerability: OSV
-- fields, the EPSS score and the CISA KEV entry. enrichment is { summary,
-- details, aliases, affectedPurls, cvssVector, cvssVersion, cvssScore, severity,
-- publishedAt, modifiedAt, epss: { score, percentile, date }, kev: { addedOn,
-- dueOn, ransomware }, references }. A summary or details a person wrote stay;
-- every other key replaces the stored value when it is present.
create or replace function ${fn("record_vulnerability_enrichment")}(tenant ${idType}, vuln_id text, enrichment jsonb)
${HEADER}
declare
  v_row ${vulnerabilities};
  v_old ${vulnerabilities};
  e jsonb := coalesce(record_vulnerability_enrichment.enrichment, '{}'::jsonb);
begin
  if not ${q.allowed("record_vulnerability_enrichment.tenant", q.write)} then
    ${q.forbidden("not allowed to change advisories")}
  end if;
  if jsonb_typeof(e) <> 'object' then
    ${q.invalid("enrichment must be an object")}
  end if;
  select * into v_old from ${vulnerabilities} y
  where y.${x("tenant")} = record_vulnerability_enrichment.tenant and y.${x("vulnId")} = record_vulnerability_enrichment.vuln_id
  for update;
  if not found then
    ${q.missing("vulnerability")}
  end if;
  update ${vulnerabilities} y set
    ${x("summary")} = coalesce(y.${x("summary")}, left(nullif(trim(e ->> 'summary'), ''), 1000)),
    ${x("details")} = coalesce(y.${x("details")}, left(nullif(trim(e ->> 'details'), ''), 20000)),
    ${x("aliases")} = case when jsonb_typeof(e -> 'aliases') = 'array'
      then (select coalesce(array_agg(distinct a order by a), '{}'::text[]) from unnest(y.${x("aliases")} || array(select jsonb_array_elements_text(e -> 'aliases'))) a)
      else y.${x("aliases")} end,
    ${x("affectedPurls")} = case when jsonb_typeof(e -> 'affectedPurls') = 'array'
      then array(select jsonb_array_elements_text(e -> 'affectedPurls'))
      else y.${x("affectedPurls")} end,
    ${x("cvssVector")} = coalesce(e ->> 'cvssVector', y.${x("cvssVector")}),
    ${x("cvssVersion")} = coalesce(e ->> 'cvssVersion', y.${x("cvssVersion")}),
    ${x("cvssScore")} = coalesce((e ->> 'cvssScore')::numeric, y.${x("cvssScore")}),
    ${x("severity")} = coalesce(e ->> 'severity', ${severityOf("(e ->> 'cvssScore')::numeric")}, y.${x("severity")}),
    ${x("publishedAt")} = coalesce((e ->> 'publishedAt')::timestamptz, y.${x("publishedAt")}),
    ${x("modifiedAt")} = coalesce((e ->> 'modifiedAt')::timestamptz, y.${x("modifiedAt")}),
    ${x("epssScore")} = case when jsonb_typeof(e -> 'epss') = 'object' then (e -> 'epss' ->> 'score')::numeric else y.${x("epssScore")} end,
    ${x("epssPercentile")} = case when jsonb_typeof(e -> 'epss') = 'object' then (e -> 'epss' ->> 'percentile')::numeric else y.${x("epssPercentile")} end,
    ${x("epssDate")} = case when jsonb_typeof(e -> 'epss') = 'object' then (e -> 'epss' ->> 'date')::date else y.${x("epssDate")} end,
    ${x("kev")} = y.${x("kev")} or jsonb_typeof(e -> 'kev') = 'object',
    ${x("kevAddedOn")} = case when jsonb_typeof(e -> 'kev') = 'object' then (e -> 'kev' ->> 'addedOn')::date else y.${x("kevAddedOn")} end,
    ${x("kevDueOn")} = case when jsonb_typeof(e -> 'kev') = 'object' then (e -> 'kev' ->> 'dueOn')::date else y.${x("kevDueOn")} end,
    ${x("kevRansomware")} = case when jsonb_typeof(e -> 'kev') = 'object' then coalesce((e -> 'kev' ->> 'ransomware')::boolean, false) else y.${x("kevRansomware")} end,
    ${x("referenceLinks")} = case when jsonb_typeof(e -> 'references') = 'array' then e -> 'references' else y.${x("referenceLinks")} end,
    ${x("enrichedAt")} = now(),
    ${x("updatedAt")} = now()
  where y.${x("id")} = v_old.${x("id")}
  returning * into v_row;
  ${rec.vulnerability("vulnerability.enriched", "v_row", false)}
  if v_row.${x("kev")} and not v_old.${x("kev")} then
    ${rec.vulnerability(
      "vulnerability.exploited",
      "v_row",
      "vulnerability added to the CISA KEV catalog",
      `, 'kevAddedOn', v_row.${x("kevAddedOn")}, 'kevDueOn', v_row.${x("kevDueOn")}`,
    )}
  end if;
  return ${vulnerabilityJson("v_row")};
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
  ${q.invalid("enrichment holds a number or date that doesn't parse")}
end;
$$;
${userGrant(`${fn("record_vulnerability_enrichment")}(${idType}, text, jsonb)`)}

-- The vulnerabilities to enrich next, never enriched first: { organizationId,
-- vulnId } rows for a cron. The service role may pass a null tenant to cover
-- every organization. stale_after defaults to one day.
create or replace function ${fn("vulnerabilities_due")}(tenant ${idType} default null, max_count integer default null, stale_after interval default null)
${HEADER}
begin
  if not ${q.allowed("vulnerabilities_due.tenant", q.write)} then
    ${q.forbidden("not allowed to change advisories")}
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('organizationId', t.${x("tenant")}, 'vulnId', t.${x("vulnId")}) order by t.${x("enrichedAt")} nulls first, t.${x("vulnId")})
    from (
      select y.* from ${vulnerabilities} y
      where (vulnerabilities_due.tenant is null or y.${x("tenant")} = vulnerabilities_due.tenant)
        and (y.${x("enrichedAt")} is null or y.${x("enrichedAt")} < now() - coalesce(vulnerabilities_due.stale_after, interval '1 day'))
      order by y.${x("enrichedAt")} nulls first, y.${x("vulnId")}
      limit ${pageSize("vulnerabilities_due.max_count", 25, 500)}
    ) t
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("vulnerabilities_due")}(${idType}, integer, interval)`)}

-- The tracked vulnerabilities: exploited ones first, then the likeliest to be
-- exploited (EPSS), then the highest CVSS score.
create or replace function ${fn("list_vulnerabilities")}(tenant ${idType}, kev_only boolean default false, max_count integer default null)
${HEADER}
begin
  if not ${q.allowed("list_vulnerabilities.tenant", q.read)} then
    ${q.forbidden("not allowed to read advisories")}
  end if;
  return coalesce((
    select jsonb_agg(${vulnerabilityJson("t")} order by t.${x("kev")} desc, t.${x("epssScore")} desc nulls last, t.${x("cvssScore")} desc nulls last, t.${x("vulnId")})
    from (
      select y.* from ${vulnerabilities} y
      where y.${x("tenant")} = list_vulnerabilities.tenant
        and (not coalesce(list_vulnerabilities.kev_only, false) or y.${x("kev")})
      order by y.${x("kev")} desc, y.${x("epssScore")} desc nulls last, y.${x("cvssScore")} desc nulls last, y.${x("vulnId")}
      limit ${pageSize("list_vulnerabilities.max_count", 200, 1000)}
    ) t
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_vulnerabilities")}(${idType}, boolean, integer)`)}
`;
}

/** The rating of a CVSS base score, as a SQL expression (null for null). */
function severityOf(score: string): string {
  return `(case when ${score} is null then null when ${score} = 0 then 'none' when ${score} < 4 then 'low' when ${score} < 7 then 'medium' when ${score} < 9 then 'high' else 'critical' end)`;
}

function vexFunctions(
  q: AdvisoriesSql,
  ctx: BlockSqlContext,
  rec: ReturnType<typeof recorders>,
): string {
  const {
    fn,
    p,
    v,
    c,
    x,
    s,
    products,
    versions,
    components,
    vulnerabilities,
    vex,
  } = q;

  const idType = ctx.idType;

  const statementJson = (row: string, vuln: string, version: string): string =>
    `jsonb_build_object('id', ${row}.${s("id")}, 'organizationId', ${row}.${s("tenant")}, 'productId', ${row}.${s("product")}, 'versionId', ${row}.${s("version")}, 'version', ${version}, 'vulnerabilityId', ${row}.${s("vulnerability")}, 'vulnId', ${vuln}, 'status', ${row}.${s("status")}, 'justification', ${row}.${s("justification")}, 'impactStatement', ${row}.${s("impactStatement")}, 'actionStatement', ${row}.${s("actionStatement")}, 'createdBy', ${row}.${s("createdBy")}, 'createdAt', ${row}.${s("createdAt")}, 'updatedAt', ${row}.${s("updatedAt")})`;

  return `
-- The tracked vulnerabilities that match components of a version by package,
-- with the product's VEX status for each. A version without its own statement
-- falls back to the statement for every version. Matching is by package, not by
-- affected version range, so each row is a candidate to triage.
create or replace function ${fn("version_exposure")}(tenant ${idType}, version_id uuid)
${HEADER}
begin
  if not ${q.allowed("version_exposure.tenant", q.read)} then
    ${q.forbidden("not allowed to read advisories")}
  end if;
  if not exists (
    select 1 from ${versions} y
    where y.${v("id")} = version_exposure.version_id and y.${v("tenant")} = version_exposure.tenant
  ) then
    ${q.missing("product version")}
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'vulnerabilityId', t.vulnerability_id, 'vulnId', t.vuln_id, 'severity', t.severity, 'cvssScore', t.cvss_score,
      'epssScore', t.epss_score, 'kev', t.kev, 'componentId', t.component_id, 'componentName', t.component_name,
      'componentVersion', t.component_version, 'purl', t.purl, 'vexStatus', t.vex_status
    ) order by t.kev desc, t.cvss_score desc nulls last, t.vuln_id, t.component_name)
    from (
      select y.${x("id")} as vulnerability_id, y.${x("vulnId")} as vuln_id, y.${x("severity")} as severity,
        y.${x("cvssScore")} as cvss_score, y.${x("epssScore")} as epss_score, y.${x("kev")} as kev,
        z.${c("id")} as component_id, z.${c("name")} as component_name, z.${c("componentVersion")} as component_version,
        z.${c("purl")} as purl,
        (select w.${s("status")} from ${vex} w
          where w.${s("tenant")} = y.${x("tenant")} and w.${s("vulnerability")} = y.${x("id")}
            and w.${s("product")} = ver.${v("product")}
            and (w.${s("version")} = ver.${v("id")} or w.${s("version")} is null)
          order by (w.${s("version")} is null) limit 1) as vex_status
      from ${versions} ver
      join ${components} z on z.${c("tenant")} = ver.${v("tenant")} and z.${c("version")} = ver.${v("id")}
      join ${vulnerabilities} y on y.${x("tenant")} = ver.${v("tenant")} and z.${c("packagePurl")} = any (y.${x("affectedPurls")})
      where ver.${v("id")} = version_exposure.version_id and ver.${v("tenant")} = version_exposure.tenant
      limit 5000
    ) t
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("version_exposure")}(${idType}, uuid)`)}

-- Sets the product's statement for a vulnerability, for one version or, with a
-- null version_id, for every version. not_affected needs a justification; the
-- other statuses take none. affected may carry an action_statement.
create or replace function ${fn("save_vex_statement")}(tenant ${idType}, product_id uuid, vulnerability_id uuid, status text, version_id uuid default null, justification text default null, impact_statement text default null, action_statement text default null)
${HEADER}
declare
  v_row ${vex};
  v_old ${vex};
  v_vuln text;
  v_label text;
begin
  if not ${q.allowed("save_vex_statement.tenant", q.write)} then
    ${q.forbidden("not allowed to change advisories")}
  end if;
  if coalesce(save_vex_statement.status, '') not in (${quoted(ADVISORY_VEX_STATUSES)}) then
    ${q.invalid(`status must be one of ${ADVISORY_VEX_STATUSES.join(", ")}`)}
  end if;
  if save_vex_statement.status = 'not_affected' and (save_vex_statement.justification is null and nullif(trim(save_vex_statement.impact_statement), '') is null) then
    ${q.invalid("not_affected needs a justification or an impact statement")}
  end if;
  if save_vex_statement.justification is not null and (save_vex_statement.status <> 'not_affected' or save_vex_statement.justification not in (${quoted(ADVISORY_VEX_JUSTIFICATIONS)})) then
    ${q.invalid("a justification applies to not_affected and is one of the OpenVEX justifications")}
  end if;
  if length(save_vex_statement.impact_statement) > 5000 or length(save_vex_statement.action_statement) > 5000 then
    ${q.invalid("impact_statement and action_statement are at most 5000 characters")}
  end if;
  if not exists (
    select 1 from ${products} y
    where y.${p("id")} = save_vex_statement.product_id and y.${p("tenant")} = save_vex_statement.tenant
  ) then
    ${q.missing("product")}
  end if;
  select y.${x("vulnId")} into v_vuln from ${vulnerabilities} y
  where y.${x("id")} = save_vex_statement.vulnerability_id and y.${x("tenant")} = save_vex_statement.tenant;
  if not found then
    ${q.missing("vulnerability")}
  end if;
  if save_vex_statement.version_id is not null and not exists (
    select 1 from ${versions} y
    where y.${v("id")} = save_vex_statement.version_id and y.${v("tenant")} = save_vex_statement.tenant
      and y.${v("product")} = save_vex_statement.product_id
  ) then
    ${q.missing("version of this product")}
  end if;
  select * into v_old from ${vex} w
  where w.${s("tenant")} = save_vex_statement.tenant and w.${s("product")} = save_vex_statement.product_id
    and w.${s("vulnerability")} = save_vex_statement.vulnerability_id
    and w.${s("version")} is not distinct from save_vex_statement.version_id
  for update;
  if v_old.${s("id")} is null then
    insert into ${vex} (${s("tenant")}, ${s("product")}, ${s("version")}, ${s("vulnerability")}, ${s("status")}, ${s("justification")}, ${s("impactStatement")}, ${s("actionStatement")}, ${s("createdBy")})
    values (save_vex_statement.tenant, save_vex_statement.product_id, save_vex_statement.version_id, save_vex_statement.vulnerability_id, save_vex_statement.status,
      save_vex_statement.justification, nullif(trim(save_vex_statement.impact_statement), ''), nullif(trim(save_vex_statement.action_statement), ''), (select auth.uid()))
    returning * into v_row;
  else
    update ${vex} w set
      ${s("status")} = save_vex_statement.status,
      ${s("justification")} = save_vex_statement.justification,
      ${s("impactStatement")} = nullif(trim(save_vex_statement.impact_statement), ''),
      ${s("actionStatement")} = nullif(trim(save_vex_statement.action_statement), ''),
      ${s("updatedAt")} = now()
    where w.${s("id")} = v_old.${s("id")}
    returning * into v_row;
  end if;
  ${rec.statement("vex_statement.saved", "v_row", "v_vuln")}
  select y.${v("version")} into v_label from ${versions} y where y.${v("id")} = v_row.${s("version")};
  return ${statementJson("v_row", "v_vuln", "v_label")};
end;
$$;
${userGrant(`${fn("save_vex_statement")}(${idType}, uuid, uuid, text, uuid, text, text, text)`)}

-- The product's statements, with the vulnerability id and version they name.
-- With version_id: the ones for that version and for every version.
create or replace function ${fn("list_vex_statements")}(tenant ${idType}, product_id uuid, version_id uuid default null)
${HEADER}
begin
  if not ${q.allowed("list_vex_statements.tenant", q.read)} then
    ${q.forbidden("not allowed to read advisories")}
  end if;
  return coalesce((
    select jsonb_agg(${statementJson("w", `y.${x("vulnId")}`, `ver.${v("version")}`)} order by y.${x("vulnId")}, ver.${v("version")} nulls first)
    from ${vex} w
    join ${vulnerabilities} y on y.${x("id")} = w.${s("vulnerability")} and y.${x("tenant")} = w.${s("tenant")}
    left join ${versions} ver on ver.${v("id")} = w.${s("version")}
    where w.${s("tenant")} = list_vex_statements.tenant and w.${s("product")} = list_vex_statements.product_id
      and (list_vex_statements.version_id is null or w.${s("version")} is null or w.${s("version")} = list_vex_statements.version_id)
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_vex_statements")}(${idType}, uuid, uuid)`)}
`;
}

function advisoryFunctions(
  q: AdvisoriesSql,
  ctx: BlockSqlContext,
  rec: ReturnType<typeof recorders>,
): string {
  const {
    fn,
    p,
    v,
    x,
    s,
    a,
    l,
    products,
    versions,
    vulnerabilities,
    vex,
    advisories,
    links,
    advisoryJson,
  } = q;

  const idType = ctx.idType;

  const published = (row: string): string => `jsonb_build_object(
    'trackingId', ${row}.${a("trackingId")}, 'title', ${row}.${a("title")}, 'summary', coalesce(${row}.${a("summary")}, ''),
    'status', ${row}.${a("status")}, 'version', ${row}.${a("revision")},
    'initialReleaseAt', ${row}.${a("initialReleaseAt")}, 'currentReleaseAt', ${row}.${a("currentReleaseAt")},
    'revisionHistory', ${row}.${a("revisionHistory")},
    'product', (select jsonb_build_object('key', y.${p("key")}, 'name', y.${p("name")},
      'versions', (select coalesce(jsonb_agg(ver.${v("version")} order by ver.${v("createdAt")}, ver.${v("version")}), '[]'::jsonb)
        from ${versions} ver where ver.${v("tenant")} = y.${p("tenant")} and ver.${v("product")} = y.${p("id")}))
      from ${products} y where y.${p("id")} = ${row}.${a("product")}),
    'vulnerabilities', (select coalesce(jsonb_agg(jsonb_build_object(
        'vulnId', z.${x("vulnId")}, 'aliases', to_jsonb(z.${x("aliases")}), 'summary', z.${x("summary")}, 'details', z.${x("details")},
        'cvssVector', z.${x("cvssVector")}, 'cvssVersion', z.${x("cvssVersion")}, 'cvssScore', z.${x("cvssScore")},
        'kevAddedOn', z.${x("kevAddedOn")},
        'statements', (select coalesce(jsonb_agg(jsonb_build_object(
            'version', ver.${v("version")}, 'status', w.${s("status")}, 'justification', w.${s("justification")},
            'impactStatement', w.${s("impactStatement")}, 'actionStatement', w.${s("actionStatement")}
          ) order by ver.${v("version")} nulls first), '[]'::jsonb)
          from ${vex} w left join ${versions} ver on ver.${v("id")} = w.${s("version")}
          where w.${s("vulnerability")} = z.${x("id")} and w.${s("product")} = ${row}.${a("product")})
      ) order by z.${x("vulnId")}), '[]'::jsonb)
      from ${links} k join ${vulnerabilities} z on z.${x("id")} = k.${l("vulnerability")}
      where k.${l("advisory")} = ${row}.${a("id")}))`;

  return `
-- Creates a draft advisory about a product and the vulnerabilities it covers,
-- or, with advisory_id, changes one. The tracking id (the CSAF tracking.id,
-- such as ACME-SA-2026-001) can't change after the first publication.
create or replace function ${fn("save_advisory")}(tenant ${idType}, tracking_id text, title text, summary text, product_id uuid, vulnerability_ids uuid[], severity text default null, advisory_id uuid default null)
${HEADER}
declare
  v_row ${advisories};
  v_old ${advisories};
  v_ids uuid[] := coalesce(save_advisory.vulnerability_ids, '{}'::uuid[]);
begin
  if not ${q.allowed("save_advisory.tenant", q.write)} then
    ${q.forbidden("not allowed to change advisories")}
  end if;
  if coalesce(save_advisory.tracking_id, '') !~ '^[A-Za-z0-9][A-Za-z0-9._-]{2,99}$' then
    ${q.invalid("tracking_id must be 3 to 100 letters, digits, dots, dashes and underscores")}
  end if;
  if coalesce(length(trim(save_advisory.title)), 0) not between 1 and 300 or length(save_advisory.summary) > 10000 then
    ${q.invalid("title must be 1 to 300 characters and summary at most 10000")}
  end if;
  if save_advisory.severity is not null and save_advisory.severity not in (${quoted(ADVISORY_SEVERITIES)}) then
    ${q.invalid(`severity must be one of ${ADVISORY_SEVERITIES.join(", ")}`)}
  end if;
  if cardinality(v_ids) > 500 then
    ${q.invalid("an advisory covers at most 500 vulnerabilities")}
  end if;
  if not exists (
    select 1 from ${products} y
    where y.${p("id")} = save_advisory.product_id and y.${p("tenant")} = save_advisory.tenant
  ) then
    ${q.missing("product")}
  end if;
  if (select count(*) from ${vulnerabilities} y where y.${x("tenant")} = save_advisory.tenant and y.${x("id")} = any (v_ids))
    <> (select count(distinct i) from unnest(v_ids) i) then
    ${q.missing("vulnerability")}
  end if;
  if save_advisory.advisory_id is not null then
    select * into v_old from ${advisories} y
    where y.${a("id")} = save_advisory.advisory_id and y.${a("tenant")} = save_advisory.tenant
    for update;
    if not found then
      ${q.missing("advisory")}
    end if;
    if v_old.${a("initialReleaseAt")} is not null and v_old.${a("trackingId")} <> save_advisory.tracking_id then
      ${q.invalid("a published advisory keeps its tracking id")}
    end if;
  end if;
  if v_old.${a("id")} is null then
    insert into ${advisories} (${a("tenant")}, ${a("trackingId")}, ${a("title")}, ${a("summary")}, ${a("product")}, ${a("severity")}, ${a("createdBy")})
    values (save_advisory.tenant, save_advisory.tracking_id, trim(save_advisory.title), nullif(trim(save_advisory.summary), ''), save_advisory.product_id, save_advisory.severity, (select auth.uid()))
    returning * into v_row;
    ${rec.advisory("advisory.created", "v_row", "advisory drafted")}
  else
    update ${advisories} y set
      ${a("trackingId")} = save_advisory.tracking_id,
      ${a("title")} = trim(save_advisory.title),
      ${a("summary")} = nullif(trim(save_advisory.summary), ''),
      ${a("product")} = save_advisory.product_id,
      ${a("severity")} = save_advisory.severity,
      ${a("updatedAt")} = now()
    where y.${a("id")} = v_old.${a("id")}
    returning * into v_row;
    ${rec.advisory("advisory.updated", "v_row", "advisory changed")}
  end if;
  delete from ${links} k where k.${l("tenant")} = v_row.${a("tenant")} and k.${l("advisory")} = v_row.${a("id")};
  insert into ${links} (${l("tenant")}, ${l("advisory")}, ${l("vulnerability")})
  select v_row.${a("tenant")}, v_row.${a("id")}, i from (select distinct unnest(v_ids) as i) d;
  return ${advisoryJson("v_row")} || jsonb_build_object('vulnerabilityIds', to_jsonb(array(select distinct unnest(v_ids))));
exception when unique_violation then
  ${q.invalid("another advisory of this organization has this tracking id")}
end;
$$;
${userGrant(`${fn("save_advisory")}(${idType}, text, text, text, uuid, uuid[], text, uuid)`)}

-- Publishes an advisory as interim or final, or publishes a new revision of one
-- already published. The CSAF document version and revision history advance on
-- every call. A final advisory can't go back to interim. Needs
-- advisories.publish.
create or replace function ${fn("publish_advisory")}(tenant ${idType}, advisory_id uuid, status text default 'final', note text default null)
${HEADER}
declare
  v_row ${advisories};
  v_old ${advisories};
  v_revision integer;
  v_now timestamptz := now();
begin
  if not ${q.allowed("publish_advisory.tenant", q.publish)} then
    ${q.forbidden("not allowed to publish advisories")}
  end if;
  if coalesce(publish_advisory.status, '') not in ('interim', 'final') then
    ${q.invalid("status must be interim or final")}
  end if;
  if length(publish_advisory.note) > 1000 then
    ${q.invalid("note is at most 1000 characters")}
  end if;
  select * into v_old from ${advisories} y
  where y.${a("id")} = publish_advisory.advisory_id and y.${a("tenant")} = publish_advisory.tenant
  for update;
  if not found then
    ${q.missing("advisory")}
  end if;
  if v_old.${a("status")} = 'final' and publish_advisory.status = 'interim' then
    ${fail("ADVISORY_FINAL", "a final advisory can't go back to interim", "55000")}
  end if;
  if not exists (select 1 from ${links} k where k.${l("tenant")} = v_old.${a("tenant")} and k.${l("advisory")} = v_old.${a("id")}) then
    ${fail("ADVISORY_EMPTY", "an advisory needs at least one vulnerability before it is published", "55000")}
  end if;
  v_revision := v_old.${a("revision")} + 1;
  update ${advisories} y set
    ${a("status")} = publish_advisory.status,
    ${a("revision")} = v_revision,
    ${a("initialReleaseAt")} = coalesce(y.${a("initialReleaseAt")}, v_now),
    ${a("currentReleaseAt")} = v_now,
    ${a("revisionHistory")} = y.${a("revisionHistory")} || jsonb_build_array(jsonb_build_object(
      'number', v_revision::text,
      'date', to_jsonb(v_now),
      'summary', coalesce(nullif(trim(publish_advisory.note), ''), case when y.${a("initialReleaseAt")} is null then 'Initial release' else 'Revised' end))),
    ${a("updatedAt")} = v_now
  where y.${a("id")} = v_old.${a("id")}
  returning * into v_row;
  ${rec.advisory("advisory.published", "v_row", "advisory published")}
  return ${advisoryJson("v_row")};
end;
$$;
${userGrant(`${fn("publish_advisory")}(${idType}, uuid, text, text)`)}

-- The organization's advisories, the newest first, optionally of one status.
create or replace function ${fn("list_advisories")}(tenant ${idType}, status text default null)
${HEADER}
begin
  if not ${q.allowed("list_advisories.tenant", q.read)} then
    ${q.forbidden("not allowed to read advisories")}
  end if;
  return coalesce((
    select jsonb_agg(${advisoryJson("y")} order by y.${a("createdAt")} desc)
    from ${advisories} y
    where y.${a("tenant")} = list_advisories.tenant
      and (list_advisories.status is null or y.${a("status")} = list_advisories.status)
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_advisories")}(${idType}, text)`)}

-- One advisory with the ids of the vulnerabilities it covers.
create or replace function ${fn("get_advisory")}(tenant ${idType}, advisory_id uuid)
${HEADER}
declare
  v_row ${advisories};
begin
  if not ${q.allowed("get_advisory.tenant", q.read)} then
    ${q.forbidden("not allowed to read advisories")}
  end if;
  select * into v_row from ${advisories} y
  where y.${a("id")} = get_advisory.advisory_id and y.${a("tenant")} = get_advisory.tenant;
  if not found then
    ${q.missing("advisory")}
  end if;
  return ${advisoryJson("v_row")} || jsonb_build_object(
    'revisionHistory', v_row.${a("revisionHistory")},
    'vulnerabilityIds', coalesce((select jsonb_agg(k.${l("vulnerability")}) from ${links} k where k.${l("tenant")} = v_row.${a("tenant")} and k.${l("advisory")} = v_row.${a("id")}), '[]'::jsonb));
end;
$$;
${userGrant(`${fn("get_advisory")}(${idType}, uuid)`)}

-- A published advisory with everything a CSAF document needs: the statements,
-- the product versions and the revision history. Service role only, for the
-- public /.well-known/csaf handler.
create or replace function ${fn("get_published_advisory")}(tenant ${idType}, tracking_id text)
${HEADER}
declare
  v_row ${advisories};
begin
  select * into v_row from ${advisories} y
  where y.${a("tenant")} = get_published_advisory.tenant and y.${a("trackingId")} = get_published_advisory.tracking_id
    and y.${a("initialReleaseAt")} is not null;
  if not found then
    ${q.missing("published advisory")}
  end if;
  return ${published("v_row")};
end;
$$;
${serviceGrant(`${fn("get_published_advisory")}(${idType}, text)`)}

-- The published advisories for the CSAF index, the newest release first.
create or replace function ${fn("list_published_advisories")}(tenant ${idType})
${HEADER}
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'trackingId', y.${a("trackingId")}, 'title', y.${a("title")}, 'status', y.${a("status")}, 'version', y.${a("revision")},
      'initialReleaseAt', y.${a("initialReleaseAt")}, 'currentReleaseAt', y.${a("currentReleaseAt")}
    ) order by y.${a("currentReleaseAt")} desc)
    from ${advisories} y
    where y.${a("tenant")} = list_published_advisories.tenant and y.${a("initialReleaseAt")} is not null
  ), '[]'::jsonb);
end;
$$;
${serviceGrant(`${fn("list_published_advisories")}(${idType})`)}
`;
}

export function advisoriesFunctions(ctx: BlockSqlContext): string {
  const q = advisoriesSql(ctx);
  const rec = recorders(q);

  return `${productFunctions(q, ctx, rec)}${sbomFunctions(q, ctx)}${vulnerabilityFunctions(q, ctx, rec)}${vexFunctions(q, ctx, rec)}${advisoryFunctions(q, ctx, rec)}`;
}
