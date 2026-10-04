import type { KitContext, KitNames } from "../context.ts";
import type { KitModuleDefinition } from "../kit.ts";

import { sqlString } from "../../core/template.ts";
import { SCHEMA, SERVICE_CALLER } from "../shared.ts";
import { hasPlatformRoles, KIT_PERMISSIONS } from "./access-model.ts";

const NAMES: KitNames = {
  options: [
    "allowPlatformTargets",
    "allowWrites",
    "auditCategory",
    "claimsHook",
    "maxTtl",
    "requireReason",
  ],
  tables: {
    sessions: {
      name: "support_sessions",
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
  },
  hooks: ["before_support_start", "after_support_start", "after_support_end"],
};

/** The session as the jsonb every function returns, with fixed keys whatever the column names. */
function sessionJson(ctx: KitContext, row: string): string {
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

function table(ctx: KitContext): string {
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
revoke all on ${sessions} from anon, authenticated;
grant select on ${sessions} to service_role;
-- Platform staff read every session.
drop policy if exists bs_support_read on ${sessions};
create policy bs_support_read on ${sessions} for select to authenticated
  using ((select ${ctx.of("access").fn("is_platform")}(${ctx.permission("view", KIT_PERMISSIONS["support-sessions"].view)})));
grant select on ${sessions} to authenticated;
`;
}

/**
 * Whether `target` holds platform permissions: the platform claim in
 * `app_metadata`, or a platform role under the catalog model. Claims your
 * access token hook adds from elsewhere are not seen here.
 */
function platformTarget(ctx: KitContext): string {
  const claim = sqlString(
    ctx.kits.access?.platformClaim ?? "platform_permissions",
  );
  const claimed = `exists (
    select 1 from auth.users u
    where u.id = target and jsonb_typeof(u.raw_app_meta_data -> ${claim}) = 'array'
      and jsonb_array_length(u.raw_app_meta_data -> ${claim}) > 0
  )`;
  if (!hasPlatformRoles(ctx)) return claimed;
  const access = ctx.of("access");
  return `(${claimed} or exists (
    select 1 from ${access.table("platformAssignments")} a
    where a.${access.col("platformAssignments", "user")} = target
  ))`;
}

/** `start_support_session`: the admin is the caller, or `admin_id` for the service role. */
function start(ctx: KitContext): string {
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
  const category = sqlString(ctx.text("auditCategory", "support"));
  return `-- Starts a support session: the admin sees the app as target until it expires
-- or ends. An admin has one active session; starting another ends the first.
-- Errors carry a code in the hint: SUPPORT_FORBIDDEN, SUPPORT_SELF,
-- SUPPORT_TARGET_MISSING, SUPPORT_TTL or SUPPORT_REASON_REQUIRED.
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
  started jsonb;
begin
  if service then
    admin := admin_id;
    if admin is null then
      raise exception 'admin_id is required for the service role' using errcode = '22023', hint = 'SUPPORT_FORBIDDEN';
    end if;
  else
    admin := auth.uid();
    if admin is null or (admin_id is not null and admin_id <> admin)
      or not ${isPlatform}(${ctx.permission("start", KIT_PERMISSIONS["support-sessions"].start)}) then
      raise exception 'Not allowed to start a support session' using errcode = '42501', hint = 'SUPPORT_FORBIDDEN';
    end if;
  end if;
  if target = admin then
    raise exception 'An admin cannot start a support session as themselves' using errcode = '22023', hint = 'SUPPORT_SELF';
  end if;
  if not exists (select 1 from auth.users u where u.id = target) then
    raise exception 'No user %', target using errcode = 'P0002', hint = 'SUPPORT_TARGET_MISSING';
  end if;
  if ttl <= interval '0' or ttl > ${maxTtl}::interval then
    raise exception 'ttl must be between 0 and %', ${maxTtl} using errcode = '22023', hint = 'SUPPORT_TTL';
  end if;${
    ctx.flag("allowPlatformTargets", false)
      ? ""
      : `
  -- Viewing the app as platform staff would hand the admin that staff's reach.
  if ${platformTarget(ctx)} then
    raise exception 'A support session cannot target platform staff' using errcode = '42501', hint = 'SUPPORT_TARGET_PLATFORM';
  end if;`
  }${
    ctx.flag("allowWrites", false)
      ? ""
      : `
  if not coalesce(read_only, true) then
    raise exception 'Support sessions are read-only (kits.support-sessions.options.allowWrites)' using errcode = '42501', hint = 'SUPPORT_WRITES_DISABLED';
  end if;`
  }${
    requireReason
      ? `
  if coalesce(btrim(reason), '') = '' then
    raise exception 'A reason is required' using errcode = '22023', hint = 'SUPPORT_REASON_REQUIRED';
  end if;`
      : ""
  }
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
  returning ${c("id")} into session_id;
  select ${sessionJson(ctx, "s")} into started from ${sessions} s where s.${c("id")} = session_id;
  perform better_supabase.audit_event(
    event_type => 'support.started',
    category => ${category},
    target_type => 'user',
    record_id => target::text,
    tenant => tenant,
    metadata => jsonb_build_object('session_id', session_id, 'reason', reason, 'read_only', read_only),
    idempotency_key => 'support.started:' || session_id,
    actor_id => admin
  );
  ${ctx.hook("after_support_start", [["uuid", "session_id"]])}
  ${ctx.emit({
    type: "support.started",
    payload: "started",
    subject: "'support_sessions/' || session_id",
    ...(ctx.has("sessions", "tenant") ? { tenant: "tenant" } : {}),
    key: "'support.started:' || session_id",
  })}
  return started;
end;
$$;`;
}

function end(ctx: KitContext): string {
  const sessions = ctx.table("sessions");
  const c = (logical: string) => ctx.col("sessions", logical);
  const isPlatform = ctx.of("access").fn("is_platform");
  const category = sqlString(ctx.text("auditCategory", "support"));
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
    raise exception 'ended_by must be admin, expired or revoked' using errcode = '22023';
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
      or ${isPlatform}(${ctx.permission("revoke", KIT_PERMISSIONS["support-sessions"].revoke)}))
  returning ${sessionJson(ctx, "s")} into ended;
  if not service then
    ended_by := case when (ended ->> 'admin_id')::uuid = auth.uid() then 'admin' else 'revoked' end;
  end if;
  if ended is null then
    return false;
  end if;
  perform better_supabase.audit_event(
    event_type => 'support.ended',
    category => ${category},
    target_type => 'user',
    record_id => ended ->> 'target_user_id',
    metadata => jsonb_build_object('session_id', session_id, 'ended_by', ended_by),
    idempotency_key => 'support.ended:' || session_id,
    actor_id => case when service then (ended ->> 'admin_id')::uuid else auth.uid() end
  );
  ${ctx.hook("after_support_end", [["uuid", "session_id"]])}
  ${ctx.emit({
    type: "support.ended",
    payload: "ended || jsonb_build_object('ended_by', ended_by)",
    subject: "'support_sessions/' || session_id",
    key: "'support.ended:' || session_id",
  })}
  return true;
end;
$$;`;
}

function reads(ctx: KitContext): string {
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
      else s.${c("admin")} = auth.uid() and ${isPlatform}(${ctx.permission("start", KIT_PERMISSIONS["support-sessions"].start)})
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
      or ${isPlatform}(${ctx.permission("view", KIT_PERMISSIONS["support-sessions"].view)}))
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
 * `kits.support.options.claimsHook`, the app's custom access token hook
 * builds them from a synthetic event, so the session sees exactly what the
 * user sees and none of the admin's claims.
 */
function claims(ctx: KitContext): string {
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
    raise exception 'No user %', target using errcode = 'P0002', hint = 'SUPPORT_TARGET_MISSING';
  end if;
${apply}
end;
$$;`;
}

function grants(ctx: KitContext): string {
  const id = ctx.idType;
  const shared = [
    `${ctx.fn("start_support_session")}(uuid, text, interval, boolean, jsonb, ${id}, uuid)`,
    `${ctx.fn("end_support_session")}(uuid, text)`,
    `${ctx.fn("active_support_session")}(uuid, uuid)`,
    `${ctx.fn("list_support_sessions")}(uuid, uuid, boolean, integer)`,
  ];
  const claimsFn = `${ctx.fn("support_target_claims")}(uuid)`;
  return [
    ...shared.map(
      (fn) => `revoke execute on function ${fn} from public, anon;
grant execute on function ${fn} to authenticated, service_role;`,
    ),
    `revoke execute on function ${claimsFn} from public, anon, authenticated;
grant execute on function ${claimsFn} to service_role;`,
  ].join("\n");
}

function build(ctx: KitContext): string {
  if (ctx.mode === "custom") return "";
  const claimsHook = ctx.text("claimsHook", "");
  if (
    claimsHook !== "" &&
    !/^[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*$/.test(claimsHook)
  ) {
    throw new TypeError(
      `kits.support-sessions.options.claimsHook must be schema.function, not "${claimsHook}"`,
    );
  }
  return [
    `${SCHEMA}${table(ctx)}`,
    start(ctx),
    end(ctx),
    reads(ctx),
    claims(ctx),
    grants(ctx),
  ].join("\n\n");
}

export const SUPPORT_SESSIONS: KitModuleDefinition = {
  name: "support-sessions",
  title: "Support sessions",
  description:
    "Lets platform staff view the app as a user: time-limited, read-only by default, gated by is_platform(), recorded in the audit log, with the target's claims built by your access token hook.",
  requires: ["access", "audit"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 1,
  names: NAMES,
  contract: () => [
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
  ],
  build,
};
