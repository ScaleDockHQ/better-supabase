import type { SupportSessionsEvents } from "../../blocks/support-sessions/events.ts";
import type { ModuleContext, ModuleEvents, ModuleNames } from "../context.ts";
import type { ModuleDefinition, ModuleLayout } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import {
  SCHEMA,
  SERVICE_CALLER,
  revokeTable,
  userGrant,
  serviceGrant,
  fail,
  raise,
} from "../shared.ts";
import {
  hasPlatformRoles,
  OPERATIONS,
  providerPlatformRoles,
} from "./access-model.ts";
import { linkedPolicy, SUPPORT_REQUEST_SUBJECT } from "./approvals.ts";
import { approverCheck, SUPPORT_SESSION_APPROVAL } from "./approver.ts";
import { READ_ONLY_GUARD } from "./drive-kit.ts";
import { supportApprovalFunctions } from "./support-approvals.ts";

const EVENTS: ModuleEvents<SupportSessionsEvents> = {
  "support.started": {
    subject: "support-sessions",
    payload: [
      "sessionId",
      "adminId",
      "targetUserId",
      "reason",
      "readOnly",
      "expiresAt",
      "organizationId",
    ],
  },
  "support.ended": {
    subject: "support-sessions",
    payload: [
      "sessionId",
      "adminId",
      "targetUserId",
      "reason",
      "readOnly",
      "expiresAt",
      "organizationId",
      "endedBy",
    ],
  },
};

const APPROVAL_MODES = ["distinct", "none"] as const;
type ApprovalMode = (typeof APPROVAL_MODES)[number];

const isApprovalMode = (value: string): value is ApprovalMode =>
  APPROVAL_MODES.some((mode) => mode === value);

const NAMES: ModuleNames = {
  events: EVENTS,
  options: [
    "allowPlatformTargets",
    "allowWrites",
    "approval",
    "approvalTtl",
    "auditCategory",
    "claimsHook",
    "maxTtl",
    "requireReason",
  ],
  tables: {
    sessions: {
      name: "support_sessions",
      lifecycle: { tenant: "tenant" },
      columns: {
        id: "id",
        admin: "admin_id",
        target: "target_user_id",
        reason: "reason",
        tenant: "organization_id",
        readOnly: "read_only",
        startedAt: "started_at",
        expiresAt: "expires_at",
        endedAt: "ended_at",
        endedBy: "ended_by",
        metadata: "metadata",
      },
      optional: ["tenant", "readOnly", "endedBy", "metadata"],
    },
    requests: {
      name: "support_requests",
      lifecycle: { tenant: "tenant" },
      columns: {
        id: "id",
        admin: "admin_id",
        target: "target_user_id",
        reason: "reason",
        tenant: "organization_id",
        readOnly: "read_only",
        metadata: "metadata",
        requestedAt: "requested_at",
        expiresAt: "expires_at",
        approvedBy: "approved_by",
        approvedAt: "approved_at",
        session: "session_id",
      },
      optionalTable: true,
    },
  },
  hooks: ["before_support_start", "after_support_start", "after_support_end"],
};

/** The session as the jsonb every function returns, with fixed keys whatever the column names. */
function sessionJson(ctx: ModuleContext, row: string): string {
  const c = (logical: string) => `${row}.${ctx.col("sessions", logical)}`;
  const optional = (logical: string, fallback: string) =>
    ctx.has("sessions", logical) ? c(logical) : fallback;
  return `jsonb_build_object(
    'id', ${c("id")},
    'admin_id', ${c("admin")},
    'target_user_id', ${c("target")},
    'reason', ${c("reason")},
    'tenant', ${optional("tenant", "null")},
    'read_only', ${optional("readOnly", "true")},
    'started_at', ${c("startedAt")},
    'expires_at', ${c("expiresAt")},
    'ended_at', ${c("endedAt")},
    'ended_by', ${optional("endedBy", "null")},
    'metadata', ${optional("metadata", "'{}'::jsonb")}
  )`;
}

/** The `SupportEventData` payload, in camelCase, from a `sessionJson` value. */
function supportPayload(session: string, extra = ""): string {
  return `jsonb_build_object('sessionId', ${session} ->> 'id', 'adminId', ${session} ->> 'admin_id', 'targetUserId', ${session} ->> 'target_user_id', 'reason', ${session} ->> 'reason', 'readOnly', (${session} ->> 'read_only')::boolean, 'expiresAt', ${session} ->> 'expires_at', 'organizationId', ${session} ->> 'tenant'${extra})`;
}

function table(ctx: ModuleContext): string {
  if (!ctx.manages) return "";
  const sessions = ctx.table("sessions");
  const c = (logical: string) => ctx.col("sessions", logical);
  return `
create table if not exists ${sessions} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  -- Sessions outlive a deleted user, so the record of who viewed whom stays.
  ${c("admin")} uuid references auth.users (id) on delete set null,
  ${c("target")} uuid references auth.users (id) on delete set null,
  ${c("reason")} text not null,
  ${c("tenant")} ${ctx.idType},
  ${c("readOnly")} boolean not null default true,
  ${c("startedAt")} timestamptz not null default now(),
  ${c("expiresAt")} timestamptz not null,
  ${c("endedAt")} timestamptz,
  ${c("endedBy")} text check (${c("endedBy")} in ('admin', 'expired', 'revoked')),
  -- App data, such as a ticket id.
  ${c("metadata")} jsonb not null default '{}',
  check (${c("admin")} <> ${c("target")}),
  check (${c("expiresAt")} > ${c("startedAt")})
);
create index if not exists support_sessions_admin_idx on ${sessions} (${c("admin")}, ${c("startedAt")} desc);
create index if not exists support_sessions_target_idx on ${sessions} (${c("target")}, ${c("startedAt")} desc);
create unique index if not exists support_sessions_one_active_idx on ${sessions} (${c("admin")}) where ${c("endedAt")} is null;
alter table ${sessions} enable row level security;
${revokeTable(sessions)}
grant select on ${sessions} to service_role;
-- Platform staff read every session.
drop policy if exists bs_support_read on ${sessions};
create policy bs_support_read on ${sessions} for select to authenticated
  using ((select ${ctx.of("access").fn("is_platform")}(${ctx.permission("view", OPERATIONS["support-sessions.view"])})));
grant select on ${sessions} to authenticated;
`;
}

/**
 * Whether the module creates the requests table: when it manages its
 * tables, or in `adopt` mode while `tables.requests` keeps its default name.
 */
function ownsRequests(ctx: ModuleContext): boolean {
  if (!ctx.hasTable("requests")) return false;
  if (ctx.manages) return true;
  const { schema, name } = ctx.tableName("requests");
  return schema === ctx.schemaName && name === NAMES.tables["requests"]!.name;
}

/** The request as the jsonb the request functions return. */
function requestJson(ctx: ModuleContext, row: string): string {
  const c = (logical: string) => `${row}.${ctx.col("requests", logical)}`;
  return `jsonb_build_object(
    'id', ${c("id")},
    'admin_id', ${c("admin")},
    'target_user_id', ${c("target")},
    'reason', ${c("reason")},
    'tenant', ${c("tenant")},
    'read_only', ${c("readOnly")},
    'metadata', ${c("metadata")},
    'requested_at', ${c("requestedAt")},
    'expires_at', ${c("expiresAt")},
    'approved_by', ${c("approvedBy")},
    'approved_at', ${c("approvedAt")},
    'session_id', ${c("session")}
  )`;
}

function requestsTable(ctx: ModuleContext): string {
  if (!ownsRequests(ctx)) return "";
  const requests = ctx.table("requests");
  const c = (logical: string) => ctx.col("requests", logical);
  const isPlatform = ctx.of("access").fn("is_platform");
  return `
-- A support session waits for a second admin: the requester asks here, and
-- another admin approves. Rows are written only through the functions below.
create table if not exists ${requests} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("admin")} uuid not null references auth.users (id) on delete cascade,
  ${c("target")} uuid not null references auth.users (id) on delete cascade,
  ${c("reason")} text not null,
  ${c("tenant")} ${ctx.idType},
  ${c("readOnly")} boolean not null default true,
  ${c("metadata")} jsonb not null default '{}',
  ${c("requestedAt")} timestamptz not null default now(),
  ${c("expiresAt")} timestamptz not null,
  ${c("approvedBy")} uuid references auth.users (id) on delete set null,
  ${c("approvedAt")} timestamptz,
  -- The session the approval started; an approval starts one session.
  ${c("session")} uuid,
  check (${c("admin")} <> ${c("target")}),
  constraint support_requests_distinct_approver check (${c("approvedBy")} <> ${c("admin")}),
  check ((${c("approvedBy")} is null) = (${c("approvedAt")} is null))
);
create index if not exists support_requests_admin_idx on ${requests} (${c("admin")}, ${c("target")}, ${c("requestedAt")} desc);
create index if not exists support_requests_target_idx on ${requests} (${c("target")});
create index if not exists support_requests_approved_by_idx on ${requests} (${c("approvedBy")});
alter table ${requests} enable row level security;
${revokeTable(requests)}
grant select on ${requests} to service_role;
-- The requester reads their own requests; platform staff read every one.
drop policy if exists bs_support_requests_read on ${requests};
create policy bs_support_requests_read on ${requests} for select to authenticated
  using (${c("admin")} = (select auth.uid())
    or (select ${isPlatform}(${ctx.permission("view", OPERATIONS["support-sessions.view"])})));
grant select on ${requests} to authenticated;
`;
}

/**
 * Whether the caller may approve the request in `row`: the provider's
 * `isApprover` with kind `support-session`, else platform staff holding the
 * approve permission (the start permission unless renamed). The requester
 * is refused before this runs.
 */
function approverOf(
  ctx: ModuleContext,
  layout: ModuleLayout,
  row: string,
): string {
  const c = (logical: string) => `${row}.${ctx.col("requests", logical)}`;
  const check = approverCheck(ctx, layout, {
    kind: SUPPORT_SESSION_APPROVAL,
    subject: `${c("id")}::text`,
    tenant: c("tenant"),
  });
  if (check) return `coalesce((${check.sql}), false)`;
  const isPlatform = ctx.of("access").fn("is_platform");
  return `${isPlatform}(${ctx.permission("approve", OPERATIONS["support-sessions.start"])})`;
}

/**
 * The approved, unused, unexpired request of `admin` for `target` in
 * `tenant` that allows `read_only`, newest first: what a start consumes.
 * The approver is never the admin, whatever the table holds.
 */
function usableRequest(
  ctx: ModuleContext,
  values: {
    readonly admin: string;
    readonly target: string;
    readonly tenant: string;
    readonly readOnly: string;
  },
): string {
  const c = (logical: string) => `x.${ctx.col("requests", logical)}`;
  return `from ${ctx.table("requests")} x
  where ${c("admin")} = ${values.admin}
    and ${c("target")} = ${values.target}
    and ${c("tenant")} is not distinct from ${values.tenant}
    and (not ${c("readOnly")} or coalesce(${values.readOnly}, true))
    and ${c("approvedBy")} is not null
    and ${c("approvedBy")} <> ${values.admin}
    and ${c("session")} is null
    and ${c("expiresAt")} > now()
  order by ${c("approvedAt")} desc
  limit 1`;
}

/** `request_support_session`, `approve_support_request` and their reads. */
function requestFunctions(ctx: ModuleContext, layout: ModuleLayout): string {
  if (!ctx.hasTable("requests")) return "";
  const requests = ctx.table("requests");
  const c = (logical: string) => ctx.col("requests", logical);
  const id = ctx.idType;
  const isPlatform = ctx.of("access").fn("is_platform");
  const startPermission = ctx.permission(
    "start",
    OPERATIONS["support-sessions.start"],
  );
  const approvalTtl = sqlString(ctx.text("approvalTtl", "1 hour"));
  const requireReason = ctx.flag("requireReason", true);
  const approvals =
    ctx.installed("approvals") && ctx.of("approvals").mode !== "custom"
      ? ctx.of("approvals")
      : undefined;
  return `-- Asks for a support session. Another admin approves it with
-- approve_support_request before start_support_session accepts it. The
-- service role passes admin_id, and approved_by for an approval the server's
-- authorization hook already decided. Errors carry a code in the hint:
-- SUPPORT_FORBIDDEN, SUPPORT_SELF, SUPPORT_SELF_APPROVAL,
-- SUPPORT_TARGET_MISSING, SUPPORT_REASON_REQUIRED or SUPPORT_WRITES_DISABLED.
create or replace function ${ctx.fn("request_support_session")}(
  target uuid,
  reason text default null,
  read_only boolean default true,
  metadata jsonb default '{}',
  tenant ${id} default null,
  admin_id uuid default null,
  approved_by uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  service boolean := ${SERVICE_CALLER};
  admin uuid;
  new_id uuid;
  requested jsonb;
begin
  if service then
    admin := admin_id;
    if admin is null then
      ${fail("SUPPORT_FORBIDDEN", "admin_id is required for the service role", "22023")}
    end if;
  else
    admin := auth.uid();
    if admin is null or (admin_id is not null and admin_id <> admin) or approved_by is not null
      or not ${isPlatform}(${startPermission}) then
      ${fail("SUPPORT_FORBIDDEN", "Not allowed to ask for a support session")}
    end if;
  end if;
  if target = admin then
    ${fail("SUPPORT_SELF", "An admin cannot start a support session as themselves", "22023")}
  end if;
  if approved_by = admin then
    ${fail("SUPPORT_SELF_APPROVAL", "An admin cannot approve their own support session")}
  end if;
  if not exists (select 1 from auth.users u where u.id = target) then
    ${raise("No user %", "P0002", "SUPPORT_TARGET_MISSING", "target")}
  end if;${
    requireReason
      ? `
  if coalesce(btrim(reason), '') = '' then
    ${fail("SUPPORT_REASON_REQUIRED", "A reason is required", "22023")}
  end if;`
      : ""
  }${
    ctx.flag("allowWrites", false)
      ? ""
      : `
  if not coalesce(read_only, true) then
    ${fail("SUPPORT_WRITES_DISABLED", 'Support sessions are read-only (blocks["support-sessions"].options.allowWrites)')}
  end if;`
  }
  insert into ${requests} (${c("admin")}, ${c("target")}, ${c("reason")}, ${c("tenant")}, ${c("readOnly")}, ${c("metadata")}, ${c("expiresAt")}, ${c("approvedBy")}, ${c("approvedAt")})
  values (admin, target, coalesce(btrim(reason), ''), tenant, coalesce(read_only, true), coalesce(metadata, '{}'),
    now() + ${approvalTtl}::interval, approved_by, case when approved_by is null then null else now() end)
  returning ${c("id")} into new_id;${
    approvals === undefined
      ? ""
      : `
  if tenant is not null and approved_by is null then
    perform ${approvals.fn("open_approval")}(
      tenant, ${sqlString(SUPPORT_REQUEST_SUBJECT)}, new_id::text, 'start', ${linkedPolicy(approvalTtl)}, coalesce(btrim(reason), ''),
      jsonb_build_object('adminId', admin, 'targetUserId', target, 'readOnly', coalesce(read_only, true))
    );
  end if;`
  }
  select ${requestJson(ctx, "x")} into requested from ${requests} x where x.${c("id")} = new_id;
  return requested;
end;
$$;

-- Approves a waiting request as a second admin. The requester never approves
-- their own request; the service role passes approver_id for an approver the
-- server's approverOf hook already allowed. Approving again as the same
-- approver returns the row. Errors carry a code in the hint:
-- SUPPORT_FORBIDDEN, SUPPORT_SELF_APPROVAL, SUPPORT_REQUEST_MISSING,
-- SUPPORT_REQUEST_CLOSED or SUPPORT_REQUEST_DECIDED.
create or replace function ${ctx.fn("approve_support_request")}(
  request_id uuid,
  approver_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  service boolean := ${SERVICE_CALLER};
  approver uuid;
  v_row ${requests};
begin
  ${READ_ONLY_GUARD}
  if service then
    approver := approver_id;
    if approver is null then
      ${fail("SUPPORT_FORBIDDEN", "approver_id is required for the service role", "22023")}
    end if;
  else
    approver := auth.uid();
    if approver is null or (approver_id is not null and approver_id <> approver) then
      ${fail("SUPPORT_FORBIDDEN", "Not allowed to approve a support session")}
    end if;
  end if;
  select * into v_row from ${requests} x where x.${c("id")} = request_id for update;
  if not found then
    ${raise("No support request %", "P0002", "SUPPORT_REQUEST_MISSING", "request_id")}
  end if;
  if v_row.${c("admin")} = approver then
    ${fail("SUPPORT_SELF_APPROVAL", "An admin cannot approve their own support session")}
  end if;
  if not service and not ${approverOf(ctx, layout, "v_row")} then
    ${fail("SUPPORT_FORBIDDEN", "Not allowed to approve this support session")}
  end if;
  return ${ctx.fn("apply_support_approval")}(request_id, approver);
end;
$$;

-- Records the approval of a waiting request, once; ${approvals === undefined ? "approve_support_request calls it after its own checks" : "approve_support_request and the approvals module call it after their own checks"}.
create or replace function ${ctx.fn("apply_support_approval")}(request_id uuid, approver uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${requests};
begin
  select * into v_row from ${requests} x where x.${c("id")} = request_id for update;
  if not found then
    ${raise("No support request %", "P0002", "SUPPORT_REQUEST_MISSING", "request_id")}
  end if;
  if approver is null then
    ${fail("SUPPORT_FORBIDDEN", "Not allowed to approve a support session")}
  end if;
  if v_row.${c("admin")} = approver then
    ${fail("SUPPORT_SELF_APPROVAL", "An admin cannot approve their own support session")}
  end if;
  if v_row.${c("approvedBy")} is not null then
    if v_row.${c("approvedBy")} = approver then
      return ${requestJson(ctx, "v_row")};
    end if;
    ${raise("Support request % is already approved", "P0001", "SUPPORT_REQUEST_DECIDED", "request_id")}
  end if;
  if v_row.${c("session")} is not null or v_row.${c("expiresAt")} <= now() then
    ${raise("Support request % has expired or was used", "P0001", "SUPPORT_REQUEST_CLOSED", "request_id")}
  end if;
  update ${requests} x set ${c("approvedBy")} = approver, ${c("approvedAt")} = now()
  where x.${c("id")} = request_id
  returning * into v_row;${
    approvals === undefined
      ? ""
      : `
  perform ${approvals.fn("approval_settle")}(${sqlString(SUPPORT_REQUEST_SUBJECT)}, request_id::text, 'start', 'approved', approver);`
  }
  return ${requestJson(ctx, "v_row")};
end;
$$;
revoke execute on function ${ctx.fn("apply_support_approval")}(uuid, uuid) from public, anon, authenticated;${
    approvals === undefined
      ? ""
      : supportApprovalFunctions(ctx, approverOf(ctx, layout, "v_row"))
  }

-- Parameters are positional below: in SQL functions a column name wins over a
-- parameter of the same name.
-- A request, for the service role, its requester and the admins who may approve it.
create or replace function ${ctx.fn("support_request")}(request_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select ${requestJson(ctx, "x")}
  from ${requests} x
  where x.${c("id")} = $1
    and (${SERVICE_CALLER} or x.${c("admin")} = auth.uid() or ${approverOf(ctx, layout, "x")})
$$;

-- The approved request a start would use, or null; the caller is the admin,
-- or admin_id for the service role.
create or replace function ${ctx.fn("approved_support_request")}(
  target uuid,
  tenant ${id} default null,
  read_only boolean default true,
  admin_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select ${requestJson(ctx, "x")}
  ${usableRequest(ctx, {
    admin: `case when ${SERVICE_CALLER} then $4 else auth.uid() end`,
    target: "$1",
    tenant: "$2",
    readOnly: "$3",
  })}
$$;`;
}

/**
 * Whether `target` holds platform permissions: the platform claim in
 * `app_metadata`, a row in the provider model's platform role table (only
 * roles that match `platformRoles.through.where`, when it is set), or a
 * platform role under the catalog model. Claims your access token hook adds
 * from elsewhere are not seen here.
 */
function platformTarget(ctx: ModuleContext): string {
  const claim = sqlString(
    ctx.modules.access?.platformClaim ?? "platform_permissions",
  );
  const claimed = `exists (
    select 1 from auth.users u
    where u.id = target and jsonb_typeof(u.raw_app_meta_data -> ${claim}) = 'array'
      and jsonb_array_length(u.raw_app_meta_data -> ${claim}) > 0
  )`;
  const platform = providerPlatformRoles(ctx);
  if (platform) {
    const through = platform.through;
    if (through?.where) {
      return `(${claimed} or exists (
    select 1 from ${platform.table} a
    join ${through.table} r on r.${through.id}::text = a.${platform.role}::text
    where a.${platform.user} = target and (${through.where.replaceAll("{row}", "r")})
  ))`;
    }
    return `(${claimed} or exists (
    select 1 from ${platform.table} a where a.${platform.user} = target
  ))`;
  }
  if (!hasPlatformRoles(ctx)) return claimed;
  const access = ctx.of("access");
  return `(${claimed} or exists (
    select 1 from ${access.table("platformAssignments")} a
    where a.${access.col("platformAssignments", "user")} = target
  ))`;
}

/** `start_support_session`: the admin is the caller, or `admin_id` for the service role. */
function start(ctx: ModuleContext): string {
  const sessions = ctx.table("sessions");
  const c = (logical: string) => ctx.col("sessions", logical);
  const id = ctx.idType;
  const isPlatform = ctx.of("access").fn("is_platform");
  const maxTtl = sqlString(ctx.text("maxTtl", "4 hours"));
  const requireReason = ctx.flag("requireReason", true);
  const columns: (readonly [string, string])[] = [
    ["admin", "admin"],
    ["target", "target"],
    ["reason", "coalesce(reason, '')"],
    ["tenant", "tenant"],
    ["readOnly", "read_only"],
    ["expiresAt", "now() + ttl"],
    ["metadata", "coalesce(metadata, '{}')"],
  ];
  const present = columns.filter(([logical]) => ctx.has("sessions", logical));
  const approval = approvalMode(ctx) === "distinct";
  const requests = approval ? ctx.table("requests") : "";
  const rc = (logical: string) => ctx.col("requests", logical);
  const approvalCheck = approval
    ? `
  -- A second admin approved this start: the approval is consumed below.
  select x.${rc("id")}, x.${rc("approvedBy")} into approval_id, approver
  ${usableRequest(ctx, { admin: "admin", target: "target", tenant: "tenant", readOnly: "read_only" })}
  for update;
  if approval_id is null then
    ${fail("SUPPORT_APPROVAL_REQUIRED", "A second admin must approve this support session (approve_support_request)")}
  end if;`
    : "";
  const consume = approval
    ? `
  update ${requests} x set ${rc("session")} = session_id where x.${rc("id")} = approval_id;`
    : "";
  return `-- Starts a support session: the admin sees the app as target until it expires
-- or ends. An admin has one active session; starting another ends the first.${
    approval
      ? `
-- It needs a request another admin approved (request_support_session, then
-- approve_support_request) for the same target, tenant and read-only flag.`
      : ""
  }
-- Errors carry a code in the hint: SUPPORT_FORBIDDEN, SUPPORT_SELF,
-- SUPPORT_TARGET_MISSING, SUPPORT_TTL, SUPPORT_REASON_REQUIRED${approval ? ", SUPPORT_APPROVAL_REQUIRED" : ""}.
create or replace function ${ctx.fn("start_support_session")}(
  target uuid,
  reason text default null,
  ttl interval default '30 minutes',
  read_only boolean default true,
  metadata jsonb default '{}',
  tenant ${id} default null,
  admin_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  service boolean := ${SERVICE_CALLER};
  admin uuid;
  session_id uuid;
  started jsonb;${
    approval
      ? `
  approval_id uuid;
  approver uuid;`
      : ""
  }
begin
  if service then
    admin := admin_id;
    if admin is null then
      ${fail("SUPPORT_FORBIDDEN", "admin_id is required for the service role", "22023")}
    end if;
  else
    admin := auth.uid();
    if admin is null or (admin_id is not null and admin_id <> admin)
      or not ${isPlatform}(${ctx.permission("start", OPERATIONS["support-sessions.start"])}) then
      ${fail("SUPPORT_FORBIDDEN", "Not allowed to start a support session")}
    end if;
  end if;
  if target = admin then
    ${fail("SUPPORT_SELF", "An admin cannot start a support session as themselves", "22023")}
  end if;
  if not exists (select 1 from auth.users u where u.id = target) then
    ${raise("No user %", "P0002", "SUPPORT_TARGET_MISSING", "target")}
  end if;
  if ttl <= interval '0' or ttl > ${maxTtl}::interval then
    ${raise("ttl must be between 0 and %", "22023", "SUPPORT_TTL", maxTtl)}
  end if;${
    ctx.flag("allowPlatformTargets", false)
      ? ""
      : `
  -- Viewing the app as platform staff would hand the admin that staff's reach.
  if ${platformTarget(ctx)} then
    ${fail("SUPPORT_TARGET_PLATFORM", "A support session cannot target platform staff")}
  end if;`
  }${
    ctx.flag("allowWrites", false)
      ? ""
      : `
  if not coalesce(read_only, true) then
    ${fail("SUPPORT_WRITES_DISABLED", 'Support sessions are read-only (blocks["support-sessions"].options.allowWrites)')}
  end if;`
  }${
    requireReason
      ? `
  if coalesce(btrim(reason), '') = '' then
    ${fail("SUPPORT_REASON_REQUIRED", "A reason is required", "22023")}
  end if;`
      : ""
  }${approvalCheck}
  ${ctx.hook("before_support_start", [
    ["uuid", "admin"],
    ["uuid", "target"],
    ["text", "reason"],
    ["jsonb", "metadata"],
  ])}
  update ${sessions} s set ${c("endedAt")} = now()${
    ctx.has("sessions", "endedBy") ? `, ${c("endedBy")} = 'admin'` : ""
  }
  where s.${c("admin")} = admin and s.${c("endedAt")} is null;
  insert into ${sessions} (${present.map(([logical]) => c(logical)).join(", ")})
  values (${present.map(([, value]) => value).join(", ")})
  returning ${c("id")} into session_id;${consume}
  select ${sessionJson(ctx, "s")} into started from ${sessions} s where s.${c("id")} = session_id;
  ${ctx.hook("after_support_start", [["uuid", "session_id"]])}
  ${ctx.record({
    type: "support.started",
    payload: supportPayload("started"),
    subject: "'support-sessions/' || session_id",
    tenant: "tenant",
    key: "'support.started:' || session_id",
    audit: {
      category: "security",
      targetType: "user",
      recordId: "target::text",
      metadata: approval
        ? "jsonb_build_object('session_id', session_id, 'reason', reason, 'read_only', read_only, 'request_id', approval_id, 'approved_by', approver)"
        : "jsonb_build_object('session_id', session_id, 'reason', reason, 'read_only', read_only)",
      actor: "admin",
      supportSession: "session_id",
      impersonatedBy: "admin",
      impersonationReason: "reason",
    },
  })}
  return started;
end;
$$;`;
}

function end(ctx: ModuleContext): string {
  const sessions = ctx.table("sessions");
  const c = (logical: string) => ctx.col("sessions", logical);
  const isPlatform = ctx.of("access").fn("is_platform");
  const tenant = ctx.has("sessions", "tenant")
    ? `(ended ->> 'tenant')::${ctx.idType}`
    : undefined;
  return `-- Ends a session. The admin who started it ends their own ('admin');
-- platform staff with the revoke permission end anyone's ('revoked'). Only
-- the service role chooses ended_by, for example 'expired' from a sweep.
create or replace function ${ctx.fn("end_support_session")}(
  session_id uuid,
  ended_by text default 'admin'
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  service boolean := ${SERVICE_CALLER};
  ended jsonb;
begin
  if service and ended_by not in ('admin', 'expired', 'revoked') then
    ${raise("ended_by must be admin, expired or revoked", "22023")}
  end if;
  update ${sessions} s set ${c("endedAt")} = now()${
    ctx.has("sessions", "endedBy")
      ? `, ${c("endedBy")} = case
      when service then ended_by
      when s.${c("admin")} = auth.uid() then 'admin'
      else 'revoked'
    end`
      : ""
  }
  where s.${c("id")} = session_id and s.${c("endedAt")} is null
    and (service or s.${c("admin")} = auth.uid()
      or ${isPlatform}(${ctx.permission("revoke", OPERATIONS["support-sessions.revoke"])}))
  returning ${sessionJson(ctx, "s")} into ended;
  if not service then
    ended_by := case when (ended ->> 'admin_id')::uuid = auth.uid() then 'admin' else 'revoked' end;
  end if;
  if ended is null then
    return false;
  end if;
  ${ctx.hook("after_support_end", [["uuid", "session_id"]])}
  ${ctx.record({
    type: "support.ended",
    payload: supportPayload("ended", ", 'endedBy', ended_by"),
    subject: "'support-sessions/' || session_id",
    ...(tenant ? { tenant } : {}),
    key: "'support.ended:' || session_id",
    audit: {
      category: "security",
      targetType: "user",
      recordId: "ended ->> 'target_user_id'",
      metadata:
        "jsonb_build_object('session_id', session_id, 'ended_by', ended_by)",
      actor:
        "case when service then (ended ->> 'admin_id')::uuid else auth.uid() end",
      supportSession: "session_id",
      impersonatedBy: "(ended ->> 'admin_id')::uuid",
      impersonationReason: "ended ->> 'reason'",
    },
  })}
  return true;
end;
$$;`;
}

/**
 * `expire_support_sessions()`: ends every running session past its expiry
 * through `end_support_session(id, 'expired')`, so each one records
 * `support.ended`, and returns the sessions it ended. Service role only.
 */
function expire(ctx: ModuleContext): string {
  const sessions = ctx.table("sessions");
  const c = (logical: string) => ctx.col("sessions", logical);
  return `-- Ends the sessions past their expiry, each with ended_by 'expired', and
-- returns them. Run it from a cron job as the service role.
create or replace function ${ctx.fn("expire_support_sessions")}()
returns setof jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  expired_id uuid;
begin
  if not (${SERVICE_CALLER}) then
    ${fail("SUPPORT_FORBIDDEN", "Only the service role expires support sessions")}
  end if;
  for expired_id in
    select s.${c("id")} from ${sessions} s
    where s.${c("endedAt")} is null and s.${c("expiresAt")} <= now()
    order by s.${c("expiresAt")}
    for update skip locked
  loop
    if ${ctx.fn("end_support_session")}(expired_id, 'expired') then
      return next (select ${sessionJson(ctx, "s")} from ${sessions} s where s.${c("id")} = expired_id);
    end if;
  end loop;
end;
$$;`;
}

function reads(ctx: ModuleContext): string {
  const sessions = ctx.table("sessions");
  const c = (logical: string) => ctx.col("sessions", logical);
  const isPlatform = ctx.of("access").fn("is_platform");
  return `-- Parameters are positional below: in SQL functions a column name wins over a
-- parameter of the same name.
-- The admin's session while it is active, or null. Read on every request
-- that carries the support cookie. Called as the admin, it also checks that
-- the admin may still start sessions.
create or replace function ${ctx.fn("active_support_session")}(
  session_id uuid,
  admin_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select ${sessionJson(ctx, "s")}
  from ${sessions} s
  where s.${c("id")} = $1
    and s.${c("endedAt")} is null
    and s.${c("expiresAt")} > now()
    and case when ${SERVICE_CALLER} then s.${c("admin")} = $2
      else s.${c("admin")} = auth.uid() and ${isPlatform}(${ctx.permission("start", OPERATIONS["support-sessions.start"])})
    end
$$;

-- Sessions, newest first, for platform staff with the view permission.
create or replace function ${ctx.fn("list_support_sessions")}(
  admin_id uuid default null,
  target uuid default null,
  active boolean default null,
  max_rows integer default 50
)
returns setof jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select ${sessionJson(ctx, "s")}
  from ${sessions} s
  where (${SERVICE_CALLER}
      or ${isPlatform}(${ctx.permission("view", OPERATIONS["support-sessions.view"])}))
    and ($1 is null or s.${c("admin")} = $1)
    and ($2 is null or s.${c("target")} = $2)
    and ($3 is null
      or $3 = (s.${c("endedAt")} is null and s.${c("expiresAt")} > now()))
  order by s.${c("startedAt")} desc
  limit $4
$$;`;
}

/**
 * `support_target_claims(target)`: the claims the target would get. With
 * `blocks.support.options.claimsHook`, the app's custom access token hook
 * builds them from a synthetic event, so the session sees exactly what the
 * user sees and none of the admin's claims.
 */
function claims(ctx: ModuleContext): string {
  const hook = ctx.text("claimsHook", "");
  const apply =
    hook === ""
      ? "  return base -> 'claims';"
      : `  return coalesce(${hook}(base) -> 'claims', base -> 'claims');`;
  return `create or replace function ${ctx.fn("support_target_claims")}(target uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  base jsonb;
begin
  select jsonb_build_object(
    'user_id', u.id,
    'authentication_method', 'support',
    'claims', jsonb_strip_nulls(jsonb_build_object(
      'sub', u.id::text,
      'aud', 'authenticated',
      'role', coalesce(nullif(u.role, ''), 'authenticated'),
      'email', u.email,
      'phone', nullif(u.phone, ''),
      'app_metadata', coalesce(u.raw_app_meta_data, '{}'),
      'user_metadata', coalesce(u.raw_user_meta_data, '{}'),
      'is_anonymous', u.is_anonymous,
      'aal', 'aal1',
      'amr', '[]'::jsonb,
      'session_id', gen_random_uuid()
    ))
  ) into base
  from auth.users u where u.id = target;
  if base is null then
    ${raise("No user %", "P0002", "SUPPORT_TARGET_MISSING", "target")}
  end if;
${apply}
end;
$$;`;
}

function grants(ctx: ModuleContext): string {
  const id = ctx.idType;
  const shared = [
    `${ctx.fn("start_support_session")}(uuid, text, interval, boolean, jsonb, ${id}, uuid)`,
    `${ctx.fn("end_support_session")}(uuid, text)`,
    `${ctx.fn("active_support_session")}(uuid, uuid)`,
    `${ctx.fn("list_support_sessions")}(uuid, uuid, boolean, integer)`,
    ...(ctx.hasTable("requests")
      ? [
          `${ctx.fn("request_support_session")}(uuid, text, boolean, jsonb, ${id}, uuid, uuid)`,
          `${ctx.fn("approve_support_request")}(uuid, uuid)`,
          `${ctx.fn("support_request")}(uuid)`,
          `${ctx.fn("approved_support_request")}(uuid, ${id}, boolean, uuid)`,
        ]
      : []),
  ];
  const serviceOnly = [
    `${ctx.fn("support_target_claims")}(uuid)`,
    `${ctx.fn("expire_support_sessions")}()`,
  ];
  return [...shared.map(userGrant), ...serviceOnly.map(serviceGrant)].join(
    "\n",
  );
}

/** `options.approval`: `distinct` (the default) or `none`. */
function approvalMode(ctx: ModuleContext): ApprovalMode {
  const mode = ctx.text("approval", "distinct");
  if (!isApprovalMode(mode)) {
    throw new TypeError(
      `blocks.support-sessions.options.approval must be ${APPROVAL_MODES.join(" or ")}, not "${mode}"`,
    );
  }
  if (mode === "distinct" && !ctx.hasTable("requests")) {
    throw new TypeError(
      'blocks.support-sessions.tables.requests is null, so starts cannot wait for a second admin; map the table or set options.approval to "none"',
    );
  }
  return mode;
}

function build(ctx: ModuleContext, layout: ModuleLayout): string {
  if (ctx.mode === "custom") return "";
  approvalMode(ctx);
  const claimsHook = ctx.text("claimsHook", "");
  if (
    claimsHook !== "" &&
    !/^[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*$/.test(claimsHook)
  ) {
    throw new TypeError(
      `blocks.support-sessions.options.claimsHook must be schema.function, not "${claimsHook}"`,
    );
  }
  return [
    `${SCHEMA}${table(ctx)}${requestsTable(ctx)}`,
    requestFunctions(ctx, layout),
    start(ctx),
    end(ctx),
    expire(ctx),
    reads(ctx),
    claims(ctx),
    grants(ctx),
  ].join("\n\n");
}

export const SUPPORT_SESSIONS: ModuleDefinition = {
  name: "support-sessions",
  scopes: ["tenant"],
  title: "Support sessions",
  description:
    "Lets platform staff view the app as a user: time-limited, read-only by default, gated by is_platform() and a second admin's approval, recorded in the audit log, with the target's claims built by your access token hook.",
  requires: ["access", "audit"],
  integrates: ["invitations", "approvals"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 2,
  names: NAMES,
  contract: (ctx) => [
    {
      name: "start_support_session",
      args: ["uuid", "text", "interval", "boolean", "jsonb", "{id}", "uuid"],
      returns: "jsonb",
    },
    { name: "end_support_session", args: ["uuid", "text"], returns: "boolean" },
    {
      name: "active_support_session",
      args: ["uuid", "uuid"],
      returns: "jsonb",
    },
    {
      name: "list_support_sessions",
      args: ["uuid", "uuid", "boolean", "integer"],
      returns: "jsonb",
    },
    { name: "support_target_claims", args: ["uuid"], returns: "jsonb" },
    { name: "expire_support_sessions", args: [], returns: "jsonb" },
    ...(ctx.hasTable("requests")
      ? [
          {
            name: "request_support_session",
            args: ["uuid", "text", "boolean", "jsonb", "{id}", "uuid", "uuid"],
            returns: "jsonb",
          },
          {
            name: "approve_support_request",
            args: ["uuid", "uuid"],
            returns: "jsonb",
          },
          { name: "support_request", args: ["uuid"], returns: "jsonb" },
          {
            name: "approved_support_request",
            args: ["uuid", "{id}", "boolean", "uuid"],
            returns: "jsonb",
          },
        ]
      : []),
  ],
  build,
};
