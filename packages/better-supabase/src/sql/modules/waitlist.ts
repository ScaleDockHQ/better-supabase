import type { WaitlistEvents } from "../../blocks/waitlist/events.ts";
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
  fail,
  lockTable,
  memberAddedRecord,
  pageSize,
  raise,
  schemaPreamble,
  SERVICE_CALLER,
  sha256Hex,
  withExtraFields,
  writeExtraColumns,
} from "../shared.ts";
import { roleValue } from "./organizations-roles.ts";
import {
  accessModel,
  moduleOperations,
  modulePermission,
  roleNames,
} from "./permissions-model.ts";

const EVENTS: BlockSqlEvents<WaitlistEvents> = {
  "waitlist.approved": {
    subject: "waitlist-entries",
    payload: ["entryId", "email"],
  },
  "waitlist.rejected": {
    subject: "waitlist-entries",
    payload: ["entryId", "email"],
  },
  "invite_code.created": {
    subject: "invite-codes",
    payload: ["codeId", "organizationId", "prefix", "role"],
  },
  "invite_code.revoked": {
    subject: "invite-codes",
    payload: ["codeId", "organizationId", "prefix", "role"],
  },
  "organization.member_added": {
    subject: "organizations",
    payload: ["organizationId", "userId", "role"],
  },
};

const ENTRY_COLUMNS = {
  id: "id",
  email: "email",
  status: "status",
  position: "position",
  referrer: "referrer",
  metadata: "metadata",
  user: "user_id",
  decidedBy: "decided_by",
  decidedAt: "decided_at",
  createdAt: "created_at",
} as const;

const CODE_COLUMNS = {
  id: "id",
  hash: "code_hash",
  prefix: "prefix",
  maxUses: "max_uses",
  uses: "uses",
  expiresAt: "expires_at",
  tenant: "organization_id",
  role: "role",
  createdBy: "created_by",
  createdAt: "created_at",
  revokedAt: "revoked_at",
} as const;

const NAMES: BlockSqlNames = {
  entities: {
    waitlist_entry: {
      table: "entries",
      singular: "waitlist_entry",
      plural: "waitlist_entries",
      primary: true,
    },
  },
  events: EVENTS,
  options: ["defaultRole", "codeField", "roles", "extraColumns"],
  tables: {
    entries: {
      name: "waitlist_entries",
      app: {},
      lifecycle: { user: "user" },
      columns: ENTRY_COLUMNS,
      optional: ["referrer", "metadata", "decidedBy", "decidedAt"],
      typed: ["status"],
    },
    codes: {
      name: "invite_codes",
      app: {},
      lifecycle: { tenant: "tenant" },
      columns: CODE_COLUMNS,
      optional: ["prefix", "expiresAt", "createdBy", "createdAt"],
      typed: ["role"],
    },
    redemptions: {
      name: "invite_code_redemptions",
      app: {},
      lifecycle: { user: "user" },
      columns: { code: "code_id", user: "user_id", redeemedAt: "redeemed_at" },
      optional: ["redeemedAt"],
    },
  },
};

const FIELD = /^[a-z][a-z0-9_]{0,62}$/;

/**
 * The roles an invite code may grant: `options.roles`, else every role of the
 * `roles` or `catalog` model but the owner. Under the `provider` and `custom`
 * models the roles are not in the config, so codes grant none unless
 * `options.roles` lists them.
 */
function assignableRoles(ctx: BlockSqlContext): readonly string[] {
  const owner = ctx.installed("organizations")
    ? ctx.of("organizations").text("ownerRole", "owner")
    : "owner";

  if (ctx.option("roles") !== undefined) {
    const roles = ctx.list("roles", []);

    if (roles.includes(owner)) {
      throw new TypeError(
        `blocks.waitlist.options.roles must not include the owner role "${owner}"`,
      );
    }

    return roles;
  }

  const model = accessModel(ctx);

  if (model !== "roles" && model !== "catalog") {
    return [];
  }

  return roleNames(ctx).filter((role) => role !== owner);
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const e = ctx.table("entries");
  const k = ctx.table("codes");
  const r = ctx.table("redemptions");
  const ce = (c: string): string => ctx.col("entries", c);
  const ck = (c: string): string => ctx.col("codes", c);
  const cr = (c: string): string => ctx.col("redemptions", c);
  const hasEntry = (c: string): boolean => ctx.has("entries", c);
  const hasCode = (c: string): boolean => ctx.has("codes", c);
  const ownsEntries = ctx.owns("entries");
  const ownsCodes = ctx.owns("codes");

  const line = (
    table: string,
    c: string,
    definition: (name: string) => string,
  ): string =>
    ctx.has(table, c)
      ? `\n  ${ctx.col(table, c)} ${definition(ctx.col(table, c))},`
      : "";

  const status = (row: string): string =>
    ownsEntries ? `${row}.${ce("status")}` : `${row}.${ce("status")}::text`;

  const role = (row: string): string =>
    ownsCodes ? `${row}.${ck("role")}` : `${row}.${ck("role")}::text`;

  // The app's table has its own column names and columns of its own, so its
  // rows go out under the module's names.
  const rowJson = (
    table: string,
    columns: Readonly<Record<string, string>>,
    row: string,
    omit?: string,
  ): string =>
    `jsonb_build_object(${Object.entries(columns)
      .filter(([logical]) => logical !== omit)
      .map(
        ([logical, key]) =>
          `'${key}', ${ctx.has(table, logical) ? `${row}.${ctx.col(table, logical)}` : "null"}`,
      )
      .join(", ")})`;

  const entryJson = (row: string): string =>
    ownsEntries ? `to_jsonb(${row})` : rowJson("entries", ENTRY_COLUMNS, row);

  const uniqueOverApp = (
    table: string,
    what: string,
    columns: readonly string[],
  ): string =>
    ctx.owns(table)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(table).name}_${what}_key`)} on ${ctx.table(table)} (${columns.map((c) => ctx.col(table, c)).join(", ")});`;

  const permissions = moduleOperations("waitlist");
  const manage = ctx.permission("manage", permissions.manage);
  const staff = ctx.staff(manage);

  const inviter = (tenant: string): string =>
    `(${staff} or (${tenant} is not null and ${ctx.can("tenant", tenant, modulePermission(ctx, "invite", permissions.invite))}))`;

  const assignable = assignableRoles(ctx);
  const roles = `array[${assignable.map(sqlString).join(", ")}]::text[]`;
  const defaultRole = ctx.text("defaultRole", "member");

  if (assignable.length > 0 && !assignable.includes(defaultRole)) {
    throw new TypeError(
      `blocks.waitlist.options.defaultRole "${defaultRole}" must be a role other than the owner (${assignable.join(", ")})`,
    );
  }

  const field = ctx.text("codeField", "invite_code");

  if (!FIELD.test(field)) {
    throw new TypeError(
      "blocks.waitlist.options.codeField must be a lowercase identifier",
    );
  }

  const tenant = ctx.of("memberships");
  const m = tenant.table("memberships");
  const mt = tenant.col("memberships", "tenant");
  const mu = tenant.col("memberships", "user");
  const mr = tenant.col("memberships", "role");
  const hash = (code: string): string => sha256Hex(`upper(trim(${code}))`);

  const usable = (row: string): string =>
    `${row}.${ck("revokedAt")} is null${hasCode("expiresAt") ? `\n      and (${row}.${ck("expiresAt")} is null or ${row}.${ck("expiresAt")} > now())` : ""}
      and (${row}.${ck("maxUses")} is null or ${row}.${ck("uses")} < ${row}.${ck("maxUses")})`;

  const publicCode = (row: string): string =>
    ownsCodes
      ? `to_jsonb(${row}) - ${sqlString(ck("hash").replaceAll('"', ""))}`
      : rowJson("codes", CODE_COLUMNS, row, "hash");

  const prefix = (row: string): string =>
    hasCode("prefix") ? `${row}.${ck("prefix")}` : "null::text";

  const codeWritten = (
    [
      ["hash", hash("create_invite_code.code")],
      ["prefix", "upper(left(trim(create_invite_code.code), 4))"],
      ["maxUses", "create_invite_code.max_uses"],
      ["expiresAt", "create_invite_code.expires_at"],
      ["tenant", "create_invite_code.tenant"],
      ["role", ctx.cast("codes", "role", "create_invite_code.role")],
      ["createdBy", "auth.uid()"],
    ] as const
  ).filter(([c]) => hasCode(c) && (c !== "createdBy" || !ownsCodes));

  const entryWritten = (
    [
      ["email", "v_email"],
      ["referrer", "join_waitlist.referrer"],
      ["metadata", "coalesce(join_waitlist.metadata, '{}'::jsonb)"],
    ] as const
  ).filter(([c]) => hasEntry(c));

  const decided = (type: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('entryId', v_row.${ce("id")}::text, 'email', v_row.${ce("email")})`,
      subject: `'waitlist-entries/' || v_row.${ce("id")}::text`,
      audit: {
        category: "access",
        targetType: "waitlist_entry",
        recordId: `v_row.${ce("id")}::text`,
        targetLabel: `v_row.${ce("email")}`,
      },
    });

  const codeEvent = (type: string, row: string, tenant: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('codeId', ${row}.${ck("id")}::text, 'organizationId', ${tenant}::text, 'prefix', ${prefix(row)}, 'role', ${row}.${ck("role")})`,
      subject: `'invite-codes/' || ${row}.${ck("id")}::text`,
      tenant,
      audit: {
        category: "access",
        targetType: "invite_code",
        recordId: `${row}.${ck("id")}::text`,
        targetLabel: prefix(row),
      },
    });

  const memberAdded = memberAddedRecord(ctx, {
    tenant: `v_code.${ck("tenant")}`,
    user: "redeem_for.member",
    role: "v_role",
  });

  const extras = ctx.extraColumns("entries", ["fields"]);
  const extra = extraFieldsArg(extras);

  return `${schemaPreamble(ctx)}
create extension if not exists pgcrypto with schema extensions;

-- People waiting for access. join_waitlist() adds them; staff approve or
-- reject; the before-user-created hook lets approved addresses sign up.
create table if not exists ${e} (
  ${ce("id")} uuid primary key default gen_random_uuid(),
  ${ce("email")} text not null unique check (${ce("email")} = lower(${ce("email")}) and ${ce("email")} ~ '^[^@[:space:]]+@[^@[:space:]]+$'),
  ${ce("status")} text not null default 'waiting' check (${ce("status")} in ('waiting', 'approved', 'rejected', 'joined')),
  ${ce("position")} bigint generated always as identity,${line("entries", "referrer", (name) => `text check (length(${name}) <= 200)`)}${line("entries", "metadata", (name) => `jsonb not null default '{}'::jsonb check (jsonb_typeof(${name}) = 'object' and pg_column_size(${name}) <= 4096)`)}
  ${ce("user")} uuid references auth.users (id) on delete set null,${line("entries", "decidedBy", () => "uuid references auth.users (id) on delete set null")}${line("entries", "decidedAt", () => "timestamptz")}
  ${ce("createdAt")} timestamptz not null default now()
);${addExtraColumns(e, extras)}
create index if not exists ${ctx.naming.rename("waitlist_entries_status_idx")} on ${e} (${ce("status")}, ${ce("position")});
create index if not exists ${ctx.naming.rename("waitlist_entries_user_idx")} on ${e} (${ce("user")});${hasEntry("decidedBy") ? `\ncreate index if not exists ${ctx.naming.rename("waitlist_entries_decided_by_idx")} on ${e} (${ce("decidedBy")});` : ""}${uniqueOverApp("entries", "email", ["email"])}
${lockTable(e)}

-- Invite codes, stored as the SHA-256 of the upper-cased code. One with an
-- organization also adds the user to it with role (or defaultRole).
create table if not exists ${k} (
  ${ck("id")} uuid primary key default gen_random_uuid(),
  ${ck("hash")} text not null unique,${line("codes", "prefix", () => "text not null")}
  ${ck("maxUses")} integer check (${ck("maxUses")} > 0),
  ${ck("uses")} integer not null default 0 check (${ck("uses")} >= 0),${line("codes", "expiresAt", () => "timestamptz")}
  ${ck("tenant")} ${id},
  ${ck("role")} text check (${ck("role")} is null or ${ck("tenant")} is not null),${line("codes", "createdBy", () => "uuid references auth.users (id) on delete set null default auth.uid()")}${line("codes", "createdAt", () => "timestamptz not null default now()")}
  ${ck("revokedAt")} timestamptz
);
create index if not exists invite_codes_tenant_idx on ${k} (${ck("tenant")});${hasCode("createdBy") ? `\ncreate index if not exists invite_codes_created_by_idx on ${k} (${ck("createdBy")});` : ""}${uniqueOverApp("codes", "hash", ["hash"])}
${lockTable(k)}

create table if not exists ${r} (
  ${cr("code")} uuid not null references ${k} (${ck("id")}) on delete cascade,
  ${cr("user")} uuid not null references auth.users (id) on delete cascade,${line("redemptions", "redeemedAt", () => "timestamptz not null default now()")}
  primary key (${cr("code")}, ${cr("user")})
);
create index if not exists invite_code_redemptions_user_idx on ${r} (${cr("user")});${uniqueOverApp("redemptions", "redeemer", ["code", "user"])}
${lockTable(r)}

-- { position, status } for an address; adding it again changes nothing.
-- Open to anon, so rate-limit the route that calls it. Only the service role
-- sees an entry's real status: everyone else reads 'waiting', and an entry that
-- left the line gets the place a new address would, so the answer never tells
-- whether someone was approved or signed up. fields: the extra columns
-- (blocks.waitlist.options.extraColumns), written only on a new entry.
${extra.drop(fn("join_waitlist"), "text, text, jsonb")}
create or replace function ${fn("join_waitlist")}(email text, referrer text default null, metadata jsonb default '{}'::jsonb${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_email text := lower(trim(join_waitlist.email));
  v_row ${e};
begin
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+$' then
    ${fail("WAITLIST_EMAIL_INVALID", "Not an email address", "22023")}
  end if;
  insert into ${e} as x (${entryWritten.map(([c]) => ce(c)).join(", ")})
  values (${entryWritten.map(([, value]) => value).join(", ")})
  on conflict (${ce("email")}) do update set ${ce("email")} = x.${ce("email")}
  returning * into v_row;${writeExtraColumns(e, extras, "join_waitlist.fields", `x.${ce("id")} = v_row.${ce("id")} and x.${ce("createdAt")} = now()`)}
  if ${SERVICE_CALLER} then
    return jsonb_build_object(
      'position', case when v_row.${ce("status")} = 'waiting' then (
        select count(*) from ${e} w where w.${ce("status")} = 'waiting' and w.${ce("position")} <= v_row.${ce("position")}
      ) end,
      'status', case when v_row.${ce("status")} = 'rejected' then 'waiting' else ${status("v_row")} end
    );
  end if;
  return jsonb_build_object(
    'position', case when v_row.${ce("status")} = 'waiting' then (
      select count(*) from ${e} w where w.${ce("status")} = 'waiting' and w.${ce("position")} <= v_row.${ce("position")}
    ) else (
      select count(*) + 1 from ${e} w where w.${ce("status")} = 'waiting'
    ) end,
    'status', 'waiting'
  );
end;
$$;

create or replace function ${fn("list_waitlist")}(status text default 'waiting', page_size integer default 50, after_position bigint default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${staff} then
    ${fail("WAITLIST_FORBIDDEN", "You may not manage the waitlist")}
  end if;
  return (
    select coalesce(jsonb_agg(${withExtraFields(entryJson("x"), "x", extras)} order by x.${ce("position")}), '[]'::jsonb)
    from (
      select * from ${e} w
      where (list_waitlist.status is null or ${status("w")} = list_waitlist.status)
        and (list_waitlist.after_position is null or w.${ce("position")} > list_waitlist.after_position)
      order by w.${ce("position")}
      limit ${pageSize("list_waitlist.page_size", 50, 500)}
    ) x
  );
end;
$$;

-- Approves or rejects an entry. Approving emits waitlist.approved, for the
-- email that says they can sign up.
create or replace function ${fn("decide_waitlist_entry")}(id uuid, approve boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${e};
begin
  if not ${staff} then
    ${fail("WAITLIST_FORBIDDEN", "You may not manage the waitlist")}
  end if;
  update ${e} x set
    ${ce("status")} = ${ctx.cast("entries", "status", "case when decide_waitlist_entry.approve then 'approved' else 'rejected' end")}${hasEntry("decidedBy") ? `,\n    ${ce("decidedBy")} = auth.uid()` : ""}${hasEntry("decidedAt") ? `,\n    ${ce("decidedAt")} = now()` : ""}
  where x.${ce("id")} = decide_waitlist_entry.id and x.${ce("status")} in ('waiting', 'approved', 'rejected')
  returning * into v_row;
  if v_row.${ce("id")} is null then
    ${raise("No open waitlist entry %", "P0002", "WAITLIST_NOT_FOUND", "decide_waitlist_entry.id")}
  end if;
  if decide_waitlist_entry.approve then
    ${decided("waitlist.approved")}
  else
    ${decided("waitlist.rejected")}
  end if;
  return ${withExtraFields(entryJson("v_row"), "v_row", extras)};
end;
$$;

-- Creates an invite code: platform staff for any, inviters (members.invite)
-- for their organization's. The app generates the code; only its hash is kept.
create or replace function ${fn("create_invite_code")}(code text, max_uses integer default 1, expires_at timestamptz default null, tenant ${id} default null, role text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${k};
begin
  if not ${inviter("create_invite_code.tenant")} then
    ${fail("WAITLIST_FORBIDDEN", "You may not create this invite code")}
  end if;
  if length(trim(create_invite_code.code)) < 8 then
    ${fail("WAITLIST_CODE_INVALID", "Invite codes need at least 8 characters", "22023")}
  end if;
  if create_invite_code.role is not null and not (create_invite_code.role = any (${roles})) then
    ${raise("An invite code can't grant role %", "22023", "WAITLIST_ROLE_INVALID", "create_invite_code.role")}
  end if;
  if create_invite_code.role is not null
    and not ${staff}
    and not coalesce(better_supabase.can_assign(create_invite_code.tenant, create_invite_code.role), false) then
    ${raise("You may not grant role %", "42501", "WAITLIST_ROLE_FORBIDDEN", "create_invite_code.role")}
  end if;
  insert into ${k} (${codeWritten.map(([c]) => ck(c)).join(", ")})
  values (
    ${codeWritten.map(([, value]) => value).join(",\n    ")}
  )
  returning * into v_row;
  ${codeEvent("invite_code.created", "v_row", `v_row.${ck("tenant")}`)}
  return ${publicCode("v_row")};
exception when unique_violation then
  ${fail("WAITLIST_CODE_TAKEN", "That invite code exists", "23505")}
end;
$$;

create or replace function ${fn("list_invite_codes")}(tenant ${id} default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${inviter("list_invite_codes.tenant")} then
    ${fail("WAITLIST_FORBIDDEN", "You may not see these invite codes")}
  end if;
  return (
    select coalesce(jsonb_agg(${publicCode("x")} order by x.${hasCode("createdAt") ? ck("createdAt") : ck("id")} desc), '[]'::jsonb)
    from ${k} x
    where x.${ck("tenant")} is not distinct from list_invite_codes.tenant
  );
end;
$$;

create or replace function ${fn("revoke_invite_code")}(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${id};
  v_code ${k};
begin
  select x.${ck("tenant")} into v_tenant from ${k} x where x.${ck("id")} = revoke_invite_code.id;
  if not found then
    return false;
  end if;
  if not ${inviter("v_tenant")} then
    ${fail("WAITLIST_FORBIDDEN", "You may not revoke this invite code")}
  end if;
  update ${k} x set ${ck("revokedAt")} = now()
  where x.${ck("id")} = revoke_invite_code.id and x.${ck("revokedAt")} is null
  returning * into v_code;
  if v_code.${ck("id")} is null then
    return false;
  end if;
  ${codeEvent("invite_code.revoked", "v_code", "v_tenant")}
  return true;
end;
$$;

-- Whether an address may sign up: approved on the waitlist, or carrying a
-- usable code. For the before-user-created hook; it consumes nothing.
create or replace function ${fn("waitlist_admit")}(email text, code text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from ${e} x
    where x.${ce("email")} = lower(trim(waitlist_admit.email)) and x.${ce("status")} in ('approved', 'joined')
  ) then
    return jsonb_build_object('allowed', true, 'reason', 'approved');
  end if;
  if waitlist_admit.code is not null and exists (
    select 1 from ${k} x where x.${ck("hash")} = ${hash("waitlist_admit.code")} and ${usable("x")}
  ) then
    return jsonb_build_object('allowed', true, 'reason', 'code');
  end if;
  return jsonb_build_object('allowed', false, 'reason', case when waitlist_admit.code is null then 'waiting' else 'code_invalid' end);
end;
$$;

-- Uses one code for member: counts it, and adds them to its organization.
-- { organizationId, role }, role null when they were a member already; or
-- raises WAITLIST_CODE_INVALID.
create or replace function ${fn("redeem_for")}(code text, member uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code ${k};
  v_role text;
  v_added boolean;
begin
  select * into v_code from ${k} x
  where x.${ck("hash")} = ${hash("redeem_for.code")}
  for update;
  if v_code.${ck("id")} is null or not (${usable("v_code")}) then
    ${fail("WAITLIST_CODE_INVALID", "This invite code is not valid", "22023")}
  end if;
  insert into ${r} (${cr("code")}, ${cr("user")}) values (v_code.${ck("id")}, redeem_for.member)
  on conflict do nothing;
  if not found then
    ${fail("WAITLIST_CODE_USED", "You already used this invite code", "23505")}
  end if;
  update ${k} x set ${ck("uses")} = x.${ck("uses")} + 1 where x.${ck("id")} = v_code.${ck("id")};
  if v_code.${ck("tenant")} is not null then
    v_role := coalesce(${role("v_code")}, ${sqlString(defaultRole)});
    insert into ${m} (${mt}, ${mu}, ${mr})
    values (v_code.${ck("tenant")}, redeem_for.member, ${roleValue(ctx, "v_role", `v_code.${ck("tenant")}`)})
    on conflict do nothing;
    v_added := found;
    if v_added then
      ${memberAdded}
    else
      v_role := null;
    end if;
  end if;
  return jsonb_build_object('organizationId', v_code.${ck("tenant")}, 'role', v_role);
end;
$$;

-- For a signed-in user, e.g. a code that joins an organization.
create or replace function ${fn("redeem_invite_code")}(code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    ${fail("WAITLIST_FORBIDDEN", "Sign in first")}
  end if;
  return ${fn("redeem_for")}(redeem_invite_code.code, auth.uid());
end;
$$;

-- On sign-up: marks the waitlist entry joined and redeems the code the
-- client passed in user metadata (${field}), then drops it from the metadata.
create or replace function ${fn("waitlist_on_auth_user")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code text := new.raw_user_meta_data ->> ${sqlString(field)};
begin
  update ${e} x set ${ce("status")} = ${ctx.cast("entries", "status", "'joined'")}, ${ce("user")} = new.id
  where x.${ce("email")} = lower(new.email) and x.${ce("status")} <> 'joined';
  if v_code is not null then
    begin
      perform ${fn("redeem_for")}(v_code, new.id);
    exception when others then
      raise warning 'better-supabase: invite code for % not redeemed: %', new.id, sqlerrm;
    end;
    update auth.users u set raw_user_meta_data = u.raw_user_meta_data - ${sqlString(field)} where u.id = new.id;
  end if;
  return null;
exception when others then
  raise warning 'better-supabase: waitlist sign-up for % failed: %', new.id, sqlerrm;
  return null;
end;
$$;
revoke execute on function ${fn("waitlist_on_auth_user")}() from public, anon, authenticated;
drop trigger if exists ${ctx.trigger("waitlist_auth_user")} on auth.users;
create trigger ${ctx.trigger("waitlist_auth_user")} after insert on auth.users
  for each row execute function ${fn("waitlist_on_auth_user")}();

revoke execute on function ${fn("join_waitlist")}(text, text, jsonb${extra.type}) from public;
revoke execute on function ${fn("list_waitlist")}(text, integer, bigint) from public, anon;
revoke execute on function ${fn("decide_waitlist_entry")}(uuid, boolean) from public, anon;
revoke execute on function ${fn("create_invite_code")}(text, integer, timestamptz, ${id}, text) from public, anon;
revoke execute on function ${fn("list_invite_codes")}(${id}) from public, anon;
revoke execute on function ${fn("revoke_invite_code")}(uuid) from public, anon;
revoke execute on function ${fn("waitlist_admit")}(text, text) from public, anon, authenticated;
revoke execute on function ${fn("redeem_for")}(text, uuid) from public, anon, authenticated;
revoke execute on function ${fn("redeem_invite_code")}(text) from public, anon;
grant execute on function ${fn("join_waitlist")}(text, text, jsonb${extra.type}) to anon, authenticated, service_role;
grant execute on function ${fn("list_waitlist")}(text, integer, bigint) to authenticated, service_role;
grant execute on function ${fn("decide_waitlist_entry")}(uuid, boolean) to authenticated, service_role;
grant execute on function ${fn("create_invite_code")}(text, integer, timestamptz, ${id}, text) to authenticated, service_role;
grant execute on function ${fn("list_invite_codes")}(${id}) to authenticated, service_role;
grant execute on function ${fn("revoke_invite_code")}(uuid) to authenticated, service_role;
grant execute on function ${fn("waitlist_admit")}(text, text) to service_role, supabase_auth_admin;
grant execute on function ${fn("redeem_for")}(text, uuid) to service_role;
grant execute on function ${fn("redeem_invite_code")}(text) to authenticated, service_role;`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "join_waitlist",
      args: [
        "text",
        "text",
        "jsonb",
        ...extraFieldsArg(ctx.extraColumns("entries", ["fields"])).contract,
      ],
      returns: "jsonb",
    },
    {
      name: "list_waitlist",
      args: ["text", "integer", "bigint"],
      returns: "jsonb",
    },
    {
      name: "decide_waitlist_entry",
      args: ["uuid", "boolean"],
      returns: "jsonb",
    },
    {
      name: "create_invite_code",
      args: ["text", "integer", "timestamptz", "{id}", "text"],
      returns: "jsonb",
    },
    { name: "list_invite_codes", args: ["{id}"], returns: "jsonb" },
    { name: "revoke_invite_code", args: ["uuid"], returns: "boolean" },
    { name: "waitlist_admit", args: ["text", "text"], returns: "jsonb" },
    { name: "redeem_for", args: ["text", "uuid"], returns: "jsonb" },
    { name: "redeem_invite_code", args: ["text"], returns: "jsonb" },
  ];
}

export const WAITLIST: BlockSqlDefinition = {
  name: "waitlist",
  scopes: ["tenant"],
  title: "Waitlist and invite codes",
  description:
    "A waitlist with positions and approvals, and hashed invite codes with a use limit, an expiry and an optional organization and role. waitlist_admit() backs a before-user-created hook that only lets approved addresses or valid codes sign up.",
  requires: ["memberships", "permissions"],
  integrates: ["invitations", "organizations"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
