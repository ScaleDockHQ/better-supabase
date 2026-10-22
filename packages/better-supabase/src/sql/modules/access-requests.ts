import type { AccessRequestsEvents } from "../../blocks/access-requests/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  addExtraColumns,
  extraFieldsArg,
  extraFieldsJson,
  fail,
  lockTable,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { accessModel, OPERATIONS, roleNames } from "./access-model.ts";
import { DURATION, policyOf, policySnapshot } from "./approvals-policies.ts";
import { ACCESS_REQUEST_SUBJECT } from "./approvals.ts";
import { roleValue } from "./organizations-roles.ts";
import { roleNameOf } from "./tenant.ts";

const WHERE = "blocks.access-requests.options";

const PAYLOAD = [
  "organizationId",
  "userId",
  "role",
  "id",
  "approvalId",
  "expiresAt",
] as const;

const EVENTS: BlockSqlEvents<AccessRequestsEvents> = {
  "access.requested": { subject: "access-requests", payload: PAYLOAD },
  "access.request_approved": { subject: "access-requests", payload: PAYLOAD },
  "access.ended": {
    subject: "access-requests",
    payload: [...PAYLOAD, "reason"],
  },
};

const NAMES: BlockSqlNames = {
  events: EVENTS,
  hooks: [
    "before_access_request",
    "after_access_request",
    "before_access_grant",
    "after_access_grant",
  ],
  options: ["roles", "policy", "maxDuration", "join", "extraColumns"],
  tables: {
    requests: {
      name: "access_requests",
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        user: "user_id",
        role: "role",
        previousRole: "previous_role",
        reason: "reason",
        duration: "duration",
        approval: "approval_id",
        grantedAt: "granted_at",
        expiresAt: "expires_at",
        endedAt: "ended_at",
        createdAt: "created_at",
      },
    },
  },
};

/** The keys a request read returns, which no extra column may shadow. */
const REQUEST_KEYS: readonly string[] = [
  "id",
  "role",
  "reason",
  "duration",
  "status",
  "fields",
];

/** `options.roles`, or every role but `owner` when the model names them. */
function requestableRoles(ctx: BlockSqlContext): readonly string[] {
  const raw = ctx.option("roles");

  if (raw === undefined) {
    return roleNames(ctx).filter((role) => role !== "owner");
  }

  if (
    !Array.isArray(raw) ||
    raw.length === 0 ||
    !raw.every((role) => typeof role === "string" && role.length > 0)
  ) {
    throw new TypeError(`${WHERE}.roles must be a non-empty list of roles`);
  }

  return raw.filter((role): role is string => typeof role === "string");
}

/** `options.policy` as an approvals policy; defaults to one approver step. */
function accessPolicy(ctx: BlockSqlContext): string {
  const raw = ctx.option("policy") ?? {
    steps: [
      {
        approvers: {
          permission: ctx.permissionKey("approve", "members.update_role"),
        },
      },
    ],
  };

  const policy = policyOf(
    ACCESS_REQUEST_SUBJECT,
    "grant",
    raw,
    `${WHERE}.policy`,
  );

  if (policy.run !== undefined) {
    throw new TypeError(
      `${WHERE}.policy.run is not allowed; the final approval grants the role`,
    );
  }

  return policySnapshot(policy);
}

function maxDuration(ctx: BlockSqlContext): string | undefined {
  const raw = ctx.option("maxDuration");

  if (raw === undefined) {
    return undefined;
  }

  if (typeof raw !== "string" || !DURATION.test(raw)) {
    throw new TypeError(
      `${WHERE}.maxDuration must be an ISO 8601 duration such as P7D`,
    );
  }

  return raw;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const requests = ctx.table("requests");
  const c = (column: string): string => ctx.col("requests", column);
  const fn = (name: string): string => ctx.fn(name);
  const approvals = ctx.of("approvals");
  const ar = approvals.table("requests");
  const a = (column: string): string => approvals.col("requests", column);
  const members = ctx.of("tenant");
  const m = members.table("memberships");
  const mu = members.col("memberships", "user");
  const mt = members.col("memberships", "tenant");
  const mr = members.col("memberships", "role");
  const read = ctx.permission("read", OPERATIONS["access-requests.read"]);
  const create = ctx.permission("create", OPERATIONS["access-requests.create"]);
  const manage = ctx.permission("manage", OPERATIONS["access-requests.manage"]);
  const extras = ctx.extraColumns("requests", REQUEST_KEYS);
  const roles = requestableRoles(ctx);
  const policy = accessPolicy(ctx);
  const max = maxDuration(ctx);
  const join = ctx.flag("join", false);
  const provider = accessModel(ctx) === "provider";

  const roleCheck =
    roles.length === 0
      ? `request_access.role = 'owner'`
      : `not (request_access.role = any (array[${roles.map(sqlString).join(", ")}]::text[]))`;

  const status = (row: string, approval: string): string =>
    `case when ${row}.${c("endedAt")} is not null then 'ended' when ${row}.${c("grantedAt")} is not null then 'granted' else coalesce(${approval}.${a("status")}, 'pending') end`;

  const json = (row: string, state: string): string =>
    `jsonb_build_object('id', ${row}.${c("id")}, 'organizationId', ${row}.${c("tenant")}, 'userId', ${row}.${c("user")}, 'role', ${row}.${c("role")}, 'previousRole', ${row}.${c("previousRole")}, 'reason', ${row}.${c("reason")}, 'duration', ${row}.${c("duration")}::text, 'status', ${state}, 'approvalId', ${row}.${c("approval")}, 'grantedAt', ${row}.${c("grantedAt")}, 'expiresAt', ${row}.${c("expiresAt")}, 'endedAt', ${row}.${c("endedAt")}, 'createdAt', ${row}.${c("createdAt")}${extraFieldsJson(row, extras)})`;

  const record = (
    event: string,
    row: string,
    extra = "",
    summary = "",
  ): string =>
    ctx.record({
      type: event,
      payload: `jsonb_build_object('organizationId', ${row}.${c("tenant")}::text, 'userId', ${row}.${c("user")}, 'role', ${row}.${c("role")}, 'id', ${row}.${c("id")}, 'approvalId', ${row}.${c("approval")}, 'expiresAt', ${row}.${c("expiresAt")}${extra})`,
      subject: `'access-requests/' || ${row}.${c("id")}::text`,
      tenant: `${row}.${c("tenant")}`,
      audit: {
        category: "membership",
        targetType: "user",
        recordId: `${row}.${c("user")}::text`,
        ...(summary === "" ? {} : { summary }),
      },
    });

  const durationCheck =
    max === undefined
      ? `
  v_duration := request_access.duration;`
      : `
  v_duration := coalesce(request_access.duration, ${sqlString(max)}::interval);
  if v_duration > ${sqlString(max)}::interval then
    ${fail("ACCESS_DURATION_INVALID", `access can last at most ${max}`, "22023")}
  end if;`;

  const grantRole = provider
    ? `
  -- The authorization provider's adapter grants the role from the event.
  null;`
    : `
  select ${roleNameOf(members, "m")} into v_previous from ${m} m
  where m.${mt} = v_row.${c("tenant")} and m.${mu} = v_row.${c("user")}
  for update;
  if found then
    update ${m} set ${mr} = ${roleValue(ctx, `v_row.${c("role")}`, `v_row.${c("tenant")}`)}
    where ${mt} = v_row.${c("tenant")} and ${mu} = v_row.${c("user")};
  else
    insert into ${m} (${mt}, ${mu}, ${mr})
    values (v_row.${c("tenant")}, v_row.${c("user")}, ${roleValue(ctx, `v_row.${c("role")}`, `v_row.${c("tenant")}`)});
  end if;`;

  const revertRole = provider
    ? ""
    : `
  -- Only a role that is still the granted one goes back; a later change wins.
  if exists (
    select 1 from ${m} m
    where m.${mt} = v_row.${c("tenant")} and m.${mu} = v_row.${c("user")}
      and ${roleNameOf(members, "m")} = v_row.${c("role")}
  ) then
    if v_row.${c("previousRole")} is null then
      delete from ${m} where ${mt} = v_row.${c("tenant")} and ${mu} = v_row.${c("user")};
    else
      update ${m} set ${mr} = ${roleValue(ctx, `v_row.${c("previousRole")}`, `v_row.${c("tenant")}`)}
      where ${mt} = v_row.${c("tenant")} and ${mu} = v_row.${c("user")};
    end if;
  end if;`;

  const tables = ctx.manages
    ? `create table if not exists ${requests} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("user")} uuid not null,
  ${c("role")} text not null check (length(${c("role")}) between 1 and 200),
  ${c("previousRole")} text,
  ${c("reason")} text check (${c("reason")} is null or length(${c("reason")}) <= 2000),
  ${c("duration")} interval check (${c("duration")} is null or ${c("duration")} > interval '0'),
  ${c("approval")} uuid references ${ar} (${a("id")}) on delete cascade,
  ${c("grantedAt")} timestamptz,
  ${c("expiresAt")} timestamptz,
  ${c("endedAt")} timestamptz,
  ${c("createdAt")} timestamptz not null default now()
);
create index if not exists ${sqlIdent(`${ctx.tableName("requests").name}_tenant_idx`)} on ${requests} (${c("tenant")}, ${c("createdAt")} desc);${addExtraColumns(requests, extras)}
create index if not exists ${sqlIdent(`${ctx.tableName("requests").name}_approval_idx`)} on ${requests} (${c("approval")}) where ${c("approval")} is not null;
create index if not exists ${sqlIdent(`${ctx.tableName("requests").name}_expiry_idx`)} on ${requests} (${c("expiresAt")}) where ${c("grantedAt")} is not null and ${c("endedAt")} is null;
${lockTable(requests, { read: true })}
drop policy if exists "access_requests_read" on ${requests};
create policy "access_requests_read" on ${requests} for select to authenticated
  using (${ctx.scope.check(c("tenant"), read)} or ${c("user")} = (select auth.uid()));
`
    : "";

  return `${schemaPreamble(ctx)}
${tables}
-- Asks for a role in an organization. Approvers come from options.policy;
-- the final approval calls grant_access_request.
${extraFieldsArg(extras).drop(fn("request_access"), `${ctx.idType}, text, text, interval`)}
create or replace function ${fn("request_access")}(tenant ${ctx.idType}, role text, reason text default null, duration interval default null${extraFieldsArg(extras).param})
returns jsonb
language plpgsql
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_current text;
  v_duration interval;
  v_row ${requests}%rowtype;
  v_approval jsonb;
begin
  if v_me is null then
    ${fail("ACCESS_SIGN_IN", "sign in to request access")}
  end if;
  select ${roleNameOf(members, "m")} into v_current from ${m} m
  where m.${mt} = request_access.tenant and m.${mu} = v_me;
  if not found then
    ${join ? "null;" : fail("ACCESS_REQUEST_FORBIDDEN", "only members can request a role")}
  elsif not ${ctx.can("tenant", "request_access.tenant", create)} then
    ${fail("ACCESS_REQUEST_FORBIDDEN", "not allowed to request a role here")}
  end if;
  if ${roleCheck} then
    ${fail("ACCESS_ROLE_INVALID", "this role can't be requested", "22023")}
  end if;
  if v_current = request_access.role then
    ${fail("ACCESS_ROLE_HELD", "you already hold this role", "22023")}
  end if;
  if v_current = 'owner' then
    ${fail("ACCESS_ROLE_INVALID", "an owner can't request another role", "22023")}
  end if;${durationCheck}
  if v_duration is not null and v_duration <= interval '0' then
    ${fail("ACCESS_DURATION_INVALID", "duration must be positive", "22023")}
  end if;
  perform pg_advisory_xact_lock(hashtextextended('access_request:' || request_access.tenant::text || ':' || v_me::text, 0));
  if exists (
    select 1 from ${requests} r join ${ar} x on x.${a("id")} = r.${c("approval")}
    where r.${c("tenant")} = request_access.tenant and r.${c("user")} = v_me and x.${a("status")} = 'pending'
  ) then
    ${fail("ACCESS_REQUEST_PENDING", "you already have a pending access request here", "23505")}
  end if;
  ${ctx.hook("before_access_request", [
    [ctx.idType, "request_access.tenant"],
    ["text", "request_access.role"],
  ])}
  insert into ${requests} (${c("tenant")}, ${c("user")}, ${c("role")}, ${c("reason")}, ${c("duration")})
  values (request_access.tenant, v_me, request_access.role, request_access.reason, v_duration)
  returning * into v_row;${writeExtraColumns(requests, extras, "request_access.fields", `x.${c("id")} = v_row.${c("id")}`, "v_row")}
  v_approval := ${approvals.fn("open_approval")}(
    request_access.tenant, ${sqlString(ACCESS_REQUEST_SUBJECT)}, v_row.${c("id")}::text, 'grant',
    ${sqlString(policy)}::jsonb, request_access.reason,
    jsonb_build_object('role', request_access.role, 'userId', v_me, 'duration', v_duration::text)
  );
  update ${requests} r set ${c("approval")} = (v_approval ->> 'id')::uuid
  where r.${c("id")} = v_row.${c("id")}
  returning * into v_row;
  ${record("access.requested", "v_row")}
  ${ctx.hook("after_access_request", [["uuid", `v_row.${c("id")}`]])}
  return ${json("v_row", "'pending'")};
end;
$$;
${userGrant(`${fn("request_access")}(${ctx.idType}, text, text, interval${extraFieldsArg(extras).type})`)}

-- Grants the role once the approval is final. Approvals calls it; it
-- isn't granted to anyone.
create or replace function ${fn("grant_access_request")}(request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${requests}%rowtype;
  v_previous text;
begin
  select * into v_row from ${requests} r where r.${c("id")} = grant_access_request.request_id for update;
  if not found or v_row.${c("grantedAt")} is not null then
    return;
  end if;
  ${ctx.hook("before_access_grant", [["uuid", `v_row.${c("id")}`]])}${grantRole}
  update ${requests} r
  set ${c("previousRole")} = v_previous,
      ${c("grantedAt")} = now(),
      ${c("expiresAt")} = case when v_row.${c("duration")} is null then null else now() + v_row.${c("duration")} end
  where r.${c("id")} = v_row.${c("id")}
  returning * into v_row;
  ${record("access.request_approved", "v_row")}
  ${ctx.hook("after_access_grant", [["uuid", `v_row.${c("id")}`]])}
end;
$$;
revoke execute on function ${fn("grant_access_request")}(uuid) from public, anon, authenticated;

-- Ends a granted role early: a manager, or the holder giving it up.
create or replace function ${fn("end_access")}(request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
declare
  v_row ${requests}%rowtype;
begin
  select * into v_row from ${requests} r where r.${c("id")} = end_access.request_id for update;
  if not found then
    ${fail("ACCESS_REQUEST_NOT_FOUND", "access request not found", "P0002")}
  end if;
  if not (${SERVICE_CALLER} or v_row.${c("user")} = auth.uid() or ${ctx.can("tenant", `v_row.${c("tenant")}`, manage)}) then
    ${fail("ACCESS_REQUEST_FORBIDDEN", "not allowed to end this access")}
  end if;
  if v_row.${c("grantedAt")} is null or v_row.${c("endedAt")} is not null then
    ${fail("ACCESS_NOT_GRANTED", "this access isn't active", "22023")}
  end if;${revertRole}
  update ${requests} r set ${c("endedAt")} = now() where r.${c("id")} = v_row.${c("id")} returning * into v_row;
  ${record("access.ended", "v_row", ", 'reason', 'revoked'")}
  return ${json("v_row", "'ended'")};
end;
$$;
${userGrant(`${fn("end_access")}(uuid)`)}

-- Ends grants past their expiry. Schedule it with pg_cron or the jobs drain.
create or replace function ${fn("expire_access_grants")}(max_grants integer default 200)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${requests}%rowtype;
  v_count integer := 0;
begin
  for v_row in
    select * from ${requests} r
    where r.${c("grantedAt")} is not null and r.${c("endedAt")} is null and r.${c("expiresAt")} <= now()
    order by r.${c("expiresAt")}
    limit greatest(coalesce(expire_access_grants.max_grants, 200), 1)
    for update skip locked
  loop${revertRole}
    update ${requests} r set ${c("endedAt")} = now() where r.${c("id")} = v_row.${c("id")} returning * into v_row;
    ${record("access.ended", "v_row", ", 'reason', 'expired'")}
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${serviceGrant(`${fn("expire_access_grants")}(integer)`)}

create or replace function ${fn("get_access_request")}(request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
declare
  v_row ${requests}%rowtype;
  v_approval ${ar}%rowtype;
begin
  select * into v_row from ${requests} r where r.${c("id")} = get_access_request.request_id;
  if not found or not (${SERVICE_CALLER} or v_row.${c("user")} = auth.uid() or ${ctx.can("tenant", `v_row.${c("tenant")}`, read)}) then
    ${fail("ACCESS_REQUEST_NOT_FOUND", "access request not found", "P0002")}
  end if;
  select * into v_approval from ${ar} x where x.${a("id")} = v_row.${c("approval")};
  return ${json("v_row", status("v_row", "v_approval"))};
end;
$$;
${userGrant(`${fn("get_access_request")}(uuid)`)}

-- Newest first. Readers of the organization see every request; others see
-- their own.
create or replace function ${fn("list_access_requests")}(tenant ${ctx.idType}, status text default null, mine boolean default false, page_size integer default null, before timestamptz default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
set intervalstyle = 'iso_8601'
as $$
  select coalesce(jsonb_agg(item order by created desc), '[]'::jsonb)
  from (
    select ${json("r", status("r", "x"))} as item, r.${c("createdAt")} as created
    from ${requests} r
    left join ${ar} x on x.${a("id")} = r.${c("approval")}
    where r.${c("tenant")} = list_access_requests.tenant
      and (r.${c("user")} = auth.uid() or (not list_access_requests.mine and (${SERVICE_CALLER} or ${ctx.can("tenant", "list_access_requests.tenant", read)})))
      and (list_access_requests.status is null or ${status("r", "x")} = list_access_requests.status)
      and (list_access_requests.before is null or r.${c("createdAt")} < list_access_requests.before)
    order by r.${c("createdAt")} desc
    limit ${pageSize("list_access_requests.page_size", 50, 200)}
  ) items
$$;
${userGrant(`${fn("list_access_requests")}(${ctx.idType}, text, boolean, integer, timestamptz)`)}
`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const extra = extraFieldsArg(
    ctx.extraColumns("requests", REQUEST_KEYS),
  ).contract;

  return [
    {
      name: "request_access",
      args: ["{id}", "text", "text", "interval", ...extra],
      returns: "jsonb",
    },
    { name: "end_access", args: ["uuid"], returns: "jsonb" },
    { name: "get_access_request", args: ["uuid"], returns: "jsonb" },
  ];
}

export const ACCESS_REQUESTS: BlockSqlDefinition = {
  name: "access-requests",
  scopes: ["tenant"],
  title: "Access requests",
  description:
    "Members ask for a role, for a set time if they like. The request goes through approvals; the final approval grants the role, and the grant ends early on request or when it expires.",
  requires: ["tenant", "access", "approvals"],
  integrates: ["outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
