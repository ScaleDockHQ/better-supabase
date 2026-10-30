import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { entityType } from "../resolved-names.ts";
import { fail, SERVICE_CALLER, userGrant } from "../shared.ts";
import { ALL_MEMBERS } from "./acknowledgements-shared.ts";
import { optionalField } from "./compliance-shared.ts";
import { moduleOperations } from "./permissions-model.ts";

/**
 * The role principal a policy that requires acknowledgement is assigned to in
 * the acknowledgements block: every member, owners and admins included.
 */
export const POLICY_ROLE: string = ALL_MEMBERS;

/**
 * The role a policy was assigned to before every member was covered. The data
 * step moves its assignments onto {@link POLICY_ROLE}.
 */
const FORMER_POLICY_ROLE = "member";

/**
 * Moves the policy assignments that name the former `member` role onto every
 * member, so policies published before the change reach owners and admins too.
 * It skips a policy that already has the every-member assignment and runs again
 * harmlessly.
 */
export function widenPolicyAssignments(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const acknowledgements = ctx.of("acknowledgements");
  const assignments = acknowledgements.table("assignments");

  const g = (column: string): string =>
    acknowledgements.col("assignments", column);

  const type = sqlString(entityType(ctx.resolved, "compliance_policy"));

  return `-- Policies assigned to the member role reach every member.
do $$
begin
  if to_regclass(${sqlString(assignments)}) is null then
    return;
  end if;
  update ${assignments} x
  set ${g("principalId")} = ${sqlString(POLICY_ROLE)}
  where x.${g("subjectType")} = ${type}
    and x.${g("principalType")} = 'role'
    and x.${g("principalId")} = ${sqlString(FORMER_POLICY_ROLE)}
    and not exists (
      select 1 from ${assignments} y
      where y.${g("tenant")} = x.${g("tenant")}
        and y.${g("subjectType")} = x.${g("subjectType")}
        and y.${g("subjectId")} = x.${g("subjectId")}
        and y.${g("principalType")} = 'role'
        and y.${g("principalId")} = ${sqlString(POLICY_ROLE)}
    );
end;
$$;`;
}

/** The policy functions of the `compliance` module. */
export function policyFunctions(ctx: BlockSqlContext): string {
  const policies = ctx.table("policies");
  const p = (column: string): string => ctx.col("policies", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const permissions = moduleOperations("compliance");
  const read = ctx.permission("read", permissions.read);
  const manage = ctx.permission("manage", permissions.manage);
  const acknowledgements = ctx.of("acknowledgements");
  const acks = acknowledgements.table("acknowledgements");

  const a = (column: string): string =>
    acknowledgements.col("acknowledgements", column);

  const members = ctx.of("memberships");
  const memberships = members.table("memberships");
  const mt = members.col("memberships", "tenant");
  const mu = members.col("memberships", "user");
  const versions = ctx.of("versions");
  const policyType = sqlString(entityType(ctx.resolved, "compliance_policy"));
  const owner = ctx.has("policies", "owner");

  const field = (row: string, column: string): string =>
    optionalField(ctx, "policies", row, column);

  const touch = ctx.has("policies", "updatedAt")
    ? `, ${p("updatedAt")} = now()`
    : "";

  const allowed = (tenant: string, permission: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", tenant, permission)})`;

  const forbidden = (message: string): string =>
    fail("COMPLIANCE_POLICY_FORBIDDEN", message);

  const notFound = fail(
    "COMPLIANCE_POLICY_NOT_FOUND",
    "policy not found",
    "P0002",
  );

  const ofPolicy = (row: string): string =>
    `ack.${a("subjectType")} = ${policyType} and ack.${a("subjectId")} = ${row}.${p("id")}::text and ack.${a("version")} = ${row}.${p("currentVersion")}`;

  const mine = (row: string): string =>
    `(select ack.${a("acknowledgedAt")} from ${acks} ack where ${ofPolicy(row)} and ack.${a("user")} = auth.uid())`;

  const acknowledged = (row: string): string =>
    `(select count(*) from ${acks} ack join ${memberships} am on am.${mt} = ack.${a("tenant")} and am.${mu} = ack.${a("user")} where ${ofPolicy(row)})`;

  const assignment = (name: string, extra: string): string =>
    `${acknowledgements.fn(name)}(v_row.${p("tenant")}, ${policyType}, v_row.${p("id")}::text, 'role', ${sqlString(POLICY_ROLE)}${extra})`;

  const policyJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${p("id")}, 'organizationId', ${row}.${p("tenant")}, 'key', ${row}.${p("key")}, 'title', ${row}.${p("title")}, 'ownerId', ${field(row, "owner")}, 'requiresAcknowledgement', ${row}.${p("requiresAck")}, 'versionId', ${row}.${p("currentVersion")}, 'versionNumber', ${row}.${p("versionNumber")}, 'publishedAt', ${row}.${p("publishedAt")}, 'archivedAt', ${row}.${p("archivedAt")}, 'createdAt', ${field(row, "createdAt")}, 'updatedAt', ${field(row, "updatedAt")}, 'acknowledgedAt', ${mine(row)}, 'acknowledgedCount', ${acknowledged(row)}, 'memberCount', (select count(*) from ${memberships} pm where pm.${mt} = ${row}.${p("tenant")}))`;

  const policyRecord = (
    type: string,
    payload: string,
    summary: string,
  ): string =>
    ctx.record({
      type,
      payload,
      subject: `'policies/' || v_row.${p("id")}::text`,
      tenant: `v_row.${p("tenant")}`,
      audit: {
        category: "data",
        targetType: "policy",
        recordId: `v_row.${p("id")}::text`,
        summary,
      },
    });

  return `
-- Creates a policy by key, or changes one (policy_id). Its text lives in the
-- versions publish_compliance_policy writes. A policy that requires
-- acknowledgement is assigned once to every member, whatever their role
-- (acknowledgements block); turning the requirement off removes that
-- assignment.
create or replace function ${fn("save_compliance_policy")}(tenant ${idType}, key text, title text, owner_id uuid default null, requires_acknowledgement boolean default true, policy_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${policies}%rowtype;
  v_required boolean;
begin
  if not ${allowed("save_compliance_policy.tenant", manage)} then
    ${forbidden("not allowed to manage policies")}
  end if;
${
  owner
    ? `  if save_compliance_policy.owner_id is not null and not exists (
    select 1 from ${memberships} m where m.${mt} = save_compliance_policy.tenant and m.${mu} = save_compliance_policy.owner_id
  ) then
    ${fail("COMPLIANCE_POLICY_INVALID", "the owner must be a member of the organization", "22023")}
  end if;
`
    : ""
}  select x.${p("requiresAck")} and x.${p("archivedAt")} is null into v_required from ${policies} x
    where x.${p("tenant")} = save_compliance_policy.tenant
      and (x.${p("id")} = save_compliance_policy.policy_id or (save_compliance_policy.policy_id is null and x.${p("key")} = save_compliance_policy.key));
  if save_compliance_policy.policy_id is null then
    insert into ${policies} (${p("tenant")}, ${p("key")}, ${p("title")}${owner ? `, ${p("owner")}` : ""}, ${p("requiresAck")})
    values (save_compliance_policy.tenant, save_compliance_policy.key, trim(save_compliance_policy.title)${owner ? ", save_compliance_policy.owner_id" : ""}, coalesce(save_compliance_policy.requires_acknowledgement, true))
    on conflict (${p("tenant")}, ${p("key")}) do update
      set ${p("title")} = excluded.${p("title")}${owner ? `, ${p("owner")} = excluded.${p("owner")}` : ""},
        ${p("requiresAck")} = excluded.${p("requiresAck")}${touch}
    returning * into v_row;
  else
    update ${policies} x set ${p("key")} = save_compliance_policy.key, ${p("title")} = trim(save_compliance_policy.title)${owner ? `, ${p("owner")} = save_compliance_policy.owner_id` : ""},
      ${p("requiresAck")} = coalesce(save_compliance_policy.requires_acknowledgement, true)${touch}
      where x.${p("id")} = save_compliance_policy.policy_id and x.${p("tenant")} = save_compliance_policy.tenant
      returning * into v_row;
    if not found then
      ${notFound}
    end if;
  end if;
  if v_row.${p("requiresAck")} and v_row.${p("archivedAt")} is null and v_required is distinct from true then
    perform ${assignment("place_acknowledgement_assignment", ", null")};
  elsif not v_row.${p("requiresAck")} and v_required then
    perform ${assignment("drop_acknowledgement_assignment", "")};
  end if;
  return ${policyJson("v_row")};
end;
$$;
${userGrant(`${fn("save_compliance_policy")}(${idType}, text, text, uuid, boolean, uuid)`)}

-- Publishes the policy text as a new frozen version (versions block) and
-- makes it current. Members acknowledge each published version again, through
-- acknowledge in the acknowledgements block.
create or replace function ${fn("publish_compliance_policy")}(policy_id uuid, content jsonb, label text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${policies}%rowtype;
  v_version jsonb;
begin
  select * into v_row from ${policies} x where x.${p("id")} = publish_compliance_policy.policy_id for update;
  if not found then
    ${notFound}
  end if;
  if not ${allowed(`v_row.${p("tenant")}`, manage)} then
    ${forbidden("not allowed to manage policies")}
  end if;
  if v_row.${p("archivedAt")} is not null then
    ${fail("COMPLIANCE_POLICY_ARCHIVED", "an archived policy can't be published", "55000")}
  end if;
  if publish_compliance_policy.content is null or jsonb_typeof(publish_compliance_policy.content) <> 'object' then
    ${fail("COMPLIANCE_POLICY_INVALID", "content must be an object", "22023")}
  end if;
  v_version := ${versions.fn("version_insert")}(
    v_row.${p("tenant")}, ${policyType}, v_row.${p("id")}::text, publish_compliance_policy.content,
    null, coalesce(publish_compliance_policy.label, v_row.${p("title")}), 'manual', true, auth.uid()
  );
  update ${policies} x set ${p("currentVersion")} = (v_version ->> 'id')::uuid,
    ${p("versionNumber")} = (v_version ->> 'number')::integer, ${p("publishedAt")} = now()${touch}
    where x.${p("id")} = v_row.${p("id")}
    returning * into v_row;
  ${policyRecord(
    "compliance_policy.published",
    `jsonb_build_object('organizationId', v_row.${p("tenant")}, 'policyId', v_row.${p("id")}, 'versionId', v_row.${p("currentVersion")}, 'number', v_row.${p("versionNumber")})`,
    `'published policy ' || v_row.${p("title")} || ' version ' || v_row.${p("versionNumber")}::text`,
  )}
  return ${policyJson("v_row")};
end;
$$;
${userGrant(`${fn("publish_compliance_policy")}(uuid, jsonb, text)`)}

-- Archives a policy and removes its every-member assignment, so members stop
-- seeing it as pending.
create or replace function ${fn("archive_compliance_policy")}(policy_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${policies}%rowtype;
begin
  select * into v_row from ${policies} x where x.${p("id")} = archive_compliance_policy.policy_id for update;
  if not found then
    ${notFound}
  end if;
  if not ${allowed(`v_row.${p("tenant")}`, manage)} then
    ${forbidden("not allowed to manage policies")}
  end if;
  update ${policies} x set ${p("archivedAt")} = coalesce(x.${p("archivedAt")}, now())${touch}
    where x.${p("id")} = v_row.${p("id")}
    returning * into v_row;
  perform ${assignment("drop_acknowledgement_assignment", "")};
  return ${policyJson("v_row")};
end;
$$;
${userGrant(`${fn("archive_compliance_policy")}(uuid)`)}

-- The policies, with the caller's acknowledgement of each current version
-- and how many members acknowledged it. list_my_acknowledgements in the
-- acknowledgements block lists the ones the caller still has to acknowledge.
create or replace function ${fn("list_compliance_policies")}(tenant ${idType}, include_archived boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${allowed("list_compliance_policies.tenant", read)} then
    ${forbidden("not allowed to read policies")}
  end if;
  return (
    select coalesce(jsonb_agg(${policyJson("x")} order by x.${p("title")}), '[]'::jsonb)
    from ${policies} x
    where x.${p("tenant")} = list_compliance_policies.tenant
      and (coalesce(list_compliance_policies.include_archived, false) or x.${p("archivedAt")} is null)
  );
end;
$$;
${userGrant(`${fn("list_compliance_policies")}(${idType}, boolean)`)}
`;
}
