import type { BlockSqlContext } from "../context.ts";
import type { ConsentPurposeContribution } from "../contributions.ts";

import { sqlString } from "../../core/template.ts";
import { uniqueContributions } from "../contributions.ts";
import { serviceGrant, userGrant } from "../shared.ts";
import { subjectTenant } from "../subject-check-sql.ts";
import { consentsSql, LEGAL_BASES, PURPOSE_KEY } from "./consents-sql.ts";

const KEY = new RegExp(PURPOSE_KEY, "u");

/** The purposes the installed blocks contribute, checked once. */
function contributedPurposes(
  ctx: BlockSqlContext,
): readonly ConsentPurposeContribution[] {
  const list = uniqueContributions(
    "consents",
    ctx.contributions("consents"),
    (each) => each.key,
  );

  for (const each of list) {
    if (!KEY.test(each.key)) {
      throw new TypeError(
        `consent purpose "${each.key}" is lowercase words joined by "_", "-" or "."`,
      );
    }

    if (
      each.legalBasis !== undefined &&
      !LEGAL_BASES.includes(each.legalBasis)
    ) {
      throw new TypeError(
        `consent purpose "${each.key}" has the unknown legal basis "${each.legalBasis}"`,
      );
    }
  }

  return list;
}

/**
 * `consent_missing` and `requires_consent`: the gate a send asks before it goes
 * out. A purpose that is unknown, archived or based on something other than
 * consent never gates, so the gate changes nothing until an app names a purpose
 * on a send (ADR 0197).
 */
export function consentGateFunctions(ctx: BlockSqlContext): string {
  const q = consentsSql(ctx);
  const { fn, c, p, purposes, consents } = q;
  const id = ctx.idType;

  const tenant = subjectTenant(
    ctx,
    "requires_consent.subject_type",
    "requires_consent.subject_id",
  );

  return `
-- Whether a send for purpose_key to record subject_type/subject_id of tenant
-- has to wait: the purpose is a current purpose of the organization (or a
-- system purpose) whose lawful basis is consent, and no consent is in force.
-- False for an unknown or archived purpose and for any other lawful basis.
-- Called by the sends of other blocks, so it is not part of the Data API.
create or replace function ${fn("consent_missing")}(tenant ${id}, subject_type text, subject_id text, purpose_key text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_purpose uuid;
  v_basis text;
begin
  if purpose_key is null or tenant is null then
    return false;
  end if;
  select x.${p("id")}, x.${p("legalBasis")}::text into v_purpose, v_basis from ${purposes} x
  where x.${p("key")} = purpose_key
    and (x.${p("tenant")} = tenant or x.${p("tenant")} is null)
    and x.${p("archivedAt")} is null
  order by (x.${p("tenant")} is null), x.${p("createdAt")} desc, x.${p("id")}
  limit 1;
  if v_purpose is null or v_basis <> 'consent' then
    return false;
  end if;
  return not exists (
    select 1 from ${consents} x
    where x.${c("tenant")} = tenant and x.${c("purpose")} = v_purpose
      and x.${c("subjectType")} = subject_type and x.${c("subjectId")} = subject_id
      and ${q.active("x")}
  );
end;
$$;
${serviceGrant(`${fn("consent_missing")}(${id}, text, text, text)`)}

-- Whether a send for purpose_key to record subject_type/subject_id has to wait
-- for consent (see consent_missing). True for a caller who can't read the
-- record's consents, so a gate never opens by mistake.
create or replace function ${fn("requires_consent")}(subject_type text, subject_id text, purpose_key text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_tenant ${id} := (${tenant})::${id};
begin
  if v_tenant is null or not ${q.readable("v_tenant", "requires_consent.subject_type", "requires_consent.subject_id")} then
    return true;
  end if;
  return ${fn("consent_missing")}(v_tenant, subject_type, subject_id, purpose_key);
end;
$$;
${userGrant(`${fn("requires_consent")}(text, text, text)`)}
`;
}

/**
 * The system purposes (no organization) the installed blocks contribute, as
 * rows for the data file. A purpose an organization already defined under the
 * key and version is left alone.
 */
export function contributedPurposeData(ctx: BlockSqlContext): string {
  const list = contributedPurposes(ctx);

  if (list.length === 0 || ctx.mode === "custom") {
    return "";
  }

  const q = consentsSql(ctx);
  const { p, purposes, has } = q;

  return `-- Consent purposes the installed blocks contribute (system purposes).
${list
  .toSorted((a, b) => a.key.localeCompare(b.key))
  .map(
    (each) =>
      `insert into ${purposes} (${p("tenant")}, ${p("key")}, ${p("title")}, ${p("legalBasis")}${has("purposes", "description") ? `, ${p("description")}` : ""})
values (null, ${sqlString(each.key)}, ${sqlString(each.title)}, ${sqlString(each.legalBasis ?? "consent")}${has("purposes", "description") ? `, ${each.description === undefined ? "null" : sqlString(each.description)}` : ""})
on conflict do nothing;`,
  )
  .join("\n")}
`;
}
