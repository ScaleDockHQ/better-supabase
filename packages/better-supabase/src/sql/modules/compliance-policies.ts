import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { entityType } from "../resolved-names.ts";
import { fail, SERVICE_CALLER, userGrant } from "../shared.ts";
import { optionalField } from "./compliance-shared.ts";
import { moduleOperations } from "./permissions-model.ts";

/** The policy and acknowledgement functions of the `compliance` module. */
export function policyFunctions(ctx: BlockSqlContext): string {
  const policies = ctx.table("policies");
  const acks = ctx.table("acknowledgements");
  const p = (column: string): string => ctx.col("policies", column);
  const a = (column: string): string => ctx.col("acknowledgements", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const permissions = moduleOperations("compliance");
  const read = ctx.permission("read", permissions.read);
  const manage = ctx.permission("manage", permissions.manage);
  const acknowledge = ctx.permission("acknowledge", permissions.acknowledge);
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

  const mine = (row: string): string =>
    `(select ack.${a("acknowledgedAt")} from ${acks} ack where ack.${a("policy")} = ${row}.${p("id")} and ack.${a("version")} = ${row}.${p("currentVersion")} and ack.${a("user")} = auth.uid())`;

  const acknowledged = (row: string): string =>
    `(select count(*) from ${acks} ack join ${memberships} am on am.${mt} = ack.${a("tenant")} and am.${mu} = ack.${a("user")} where ack.${a("policy")} = ${row}.${p("id")} and ack.${a("version")} = ${row}.${p("currentVersion")})`;

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
-- versions publish_compliance_policy writes.
create or replace function ${fn("save_compliance_policy")}(tenant ${idType}, key text, title text, owner_id uuid default null, requires_acknowledgement boolean default true, policy_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${policies}%rowtype;
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
}  if save_compliance_policy.policy_id is null then
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
  return ${policyJson("v_row")};
end;
$$;
${userGrant(`${fn("save_compliance_policy")}(${idType}, text, text, uuid, boolean, uuid)`)}

-- Publishes the policy text as a new frozen version (versions block) and
-- makes it current. Members acknowledge each published version again.
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
  return ${policyJson("v_row")};
end;
$$;
${userGrant(`${fn("archive_compliance_policy")}(uuid)`)}

-- The caller acknowledges the policy's current version. A second call keeps
-- the first acknowledgement.
create or replace function ${fn("acknowledge_compliance_policy")}(policy_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${policies}%rowtype;
  v_me uuid := auth.uid();
begin
  select * into v_row from ${policies} x where x.${p("id")} = acknowledge_compliance_policy.policy_id;
  if not found then
    ${notFound}
  end if;
  if v_me is null or not ${ctx.can("tenant", `v_row.${p("tenant")}`, acknowledge)} then
    ${forbidden("not allowed to acknowledge policies")}
  end if;
  if v_row.${p("currentVersion")} is null or v_row.${p("archivedAt")} is not null then
    ${fail("COMPLIANCE_POLICY_NOT_PUBLISHED", "the policy has no published version to acknowledge", "55000")}
  end if;
  insert into ${acks} (${a("tenant")}, ${a("policy")}, ${a("version")}, ${a("user")})
  values (v_row.${p("tenant")}, v_row.${p("id")}, v_row.${p("currentVersion")}, v_me)
  on conflict (${a("policy")}, ${a("version")}, ${a("user")}) do nothing;
  if found then
    ${policyRecord(
      "compliance_policy.acknowledged",
      `jsonb_build_object('organizationId', v_row.${p("tenant")}, 'policyId', v_row.${p("id")}, 'versionId', v_row.${p("currentVersion")}, 'userId', v_me)`,
      `'acknowledged policy ' || v_row.${p("title")} || ' version ' || v_row.${p("versionNumber")}::text`,
    )}
  end if;
  return ${policyJson("v_row")};
end;
$$;
${userGrant(`${fn("acknowledge_compliance_policy")}(uuid)`)}

-- The policies, with the caller's acknowledgement of each current version
-- and how many members acknowledged it. pending_only: the published policies
-- that need the caller's acknowledgement.
create or replace function ${fn("list_compliance_policies")}(tenant ${idType}, include_archived boolean default false, pending_only boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (${allowed("list_compliance_policies.tenant", read)} or ${ctx.can("tenant", "list_compliance_policies.tenant", acknowledge)}) then
    ${forbidden("not allowed to read policies")}
  end if;
  return (
    select coalesce(jsonb_agg(${policyJson("x")} order by x.${p("title")}), '[]'::jsonb)
    from ${policies} x
    where x.${p("tenant")} = list_compliance_policies.tenant
      and (coalesce(list_compliance_policies.include_archived, false) or x.${p("archivedAt")} is null)
      and (not coalesce(list_compliance_policies.pending_only, false) or (
        x.${p("requiresAck")} and x.${p("currentVersion")} is not null and x.${p("archivedAt")} is null and ${mine("x")} is null
      ))
  );
end;
$$;
${userGrant(`${fn("list_compliance_policies")}(${idType}, boolean, boolean)`)}

-- Every member and when they acknowledged the policy's current version
-- (null: not yet), for the policy's owner and compliance reviewers.
create or replace function ${fn("compliance_policy_acknowledgements")}(policy_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${policies}%rowtype;
begin
  select * into v_row from ${policies} x where x.${p("id")} = compliance_policy_acknowledgements.policy_id;
  if not found then
    ${notFound}
  end if;
  if not ${allowed(`v_row.${p("tenant")}`, read)} then
    ${forbidden("not allowed to read policy acknowledgements")}
  end if;
  return jsonb_build_object(
    'id', v_row.${p("id")},
    'versionId', v_row.${p("currentVersion")},
    'versionNumber', v_row.${p("versionNumber")},
    'members', (
      select coalesce(jsonb_agg(jsonb_build_object('userId', m.${mu}, 'acknowledgedAt', ack.${a("acknowledgedAt")})
        order by ack.${a("acknowledgedAt")} nulls first, m.${mu}), '[]'::jsonb)
      from ${memberships} m
      left join ${acks} ack on ack.${a("policy")} = v_row.${p("id")} and ack.${a("version")} = v_row.${p("currentVersion")} and ack.${a("user")} = m.${mu}
      where m.${mt} = v_row.${p("tenant")}
    )
  );
end;
$$;
${userGrant(`${fn("compliance_policy_acknowledgements")}(uuid)`)}
`;
}
