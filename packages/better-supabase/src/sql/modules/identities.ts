import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import {
  fail,
  lockTable,
  revokeTable,
  schemaPreamble,
  serviceGrant,
  sha256Hex,
  userGrant,
} from "../shared.ts";

const NAMES: BlockSqlNames = {
  options: ["codeMinutes", "verifiedEmails"],
  tables: {
    links: {
      name: "identity_links",
      lifecycle: { user: "user" },
      columns: {
        id: "id",
        kind: "kind",
        provider: "provider",
        value: "value",
        workspace: "workspace",
        user: "user_id",
        contact: "contact_id",
        source: "source",
        createdAt: "created_at",
      },
    },
    codes: {
      name: "identity_link_codes",
      lifecycle: { user: "user", export: false },
      columns: {
        id: "id",
        user: "user_id",
        kind: "kind",
        provider: "provider",
        codeHash: "code_hash",
        expiresAt: "expires_at",
        usedAt: "used_at",
        createdAt: "created_at",
      },
    },
  },
};

const KINDS = "'email', 'chat'";

function build(ctx: BlockSqlContext): string {
  const links = ctx.table("links");
  const codes = ctx.table("codes");
  const l = (column: string): string => ctx.col("links", column);
  const c = (column: string): string => ctx.col("codes", column);
  const fn = (name: string): string => ctx.fn(name);

  const minutes = Math.max(
    1,
    Math.min(60, Math.trunc(ctx.number("codeMinutes", 10))),
  );

  const contactRef = ctx.installed("inbox")
    ? ` references ${ctx.of("inbox").table("contacts")} (${ctx.of("inbox").col("contacts", "id")}) on delete cascade`
    : "";

  const verified = ctx.flag("verifiedEmails", true);
  const trigger = ctx.trigger("identity_email");

  const emailTrigger = verified
    ? `
-- Keeps the email identity of each user equal to the confirmed address in
-- auth.users. An address another user or contact holds stays theirs.
create or replace function ${fn("on_auth_user_email")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    if tg_op = 'UPDATE' and old.email is distinct from new.email then
      delete from ${links}
      where ${l("user")} = new.id and ${l("kind")} = 'email' and ${l("source")} = 'verified_email';
    end if;
    perform ${fn("link_verified_email")}(new.id);
  exception when others then
    raise warning 'No email identity for user %: % (SQLSTATE %)', new.id, sqlerrm, sqlstate;
  end;
  return new;
end;
$$;
revoke execute on function ${fn("on_auth_user_email")}() from public, anon, authenticated;
drop trigger if exists ${trigger} on auth.users;
create trigger ${trigger} after insert or update of email, email_confirmed_at on auth.users
  for each row execute function ${fn("on_auth_user_email")}();`
    : `drop trigger if exists ${trigger} on auth.users;`;

  return `${schemaPreamble(ctx)}
-- Maps an email address or a chat user to an app user or a contact. Rows
-- come from a link code the signed-in user issued and the service redeemed
-- (redeem_identity_link), or from a confirmed address in auth.users
-- (link_verified_email). Users read and delete their own; nobody inserts or
-- updates directly.
create table if not exists ${links} (
  ${l("id")} uuid primary key default gen_random_uuid(),
  ${l("kind")} text not null check (${l("kind")} in (${KINDS})),
  ${l("provider")} text check (length(${l("provider")}) between 1 and 100),
  ${l("value")} text not null check (length(${l("value")}) between 1 and 500),
  ${l("workspace")} text check (length(${l("workspace")}) between 1 and 200),
  ${l("user")} uuid references auth.users (id) on delete cascade,
  ${l("contact")} uuid${contactRef},
  ${l("source")} text not null check (${l("source")} in ('link', 'verified_email')),
  ${l("createdAt")} timestamptz not null default now(),
  constraint identity_links_one_target check (num_nonnulls(${l("user")}, ${l("contact")}) = 1),
  constraint identity_links_email_lower check (${l("kind")} <> 'email' or ${l("value")} = lower(${l("value")})),
  constraint identity_links_identity_key unique nulls not distinct (${l("kind")}, ${l("provider")}, ${l("value")}, ${l("workspace")})
);
create index if not exists identity_links_user_idx on ${links} (${l("user")});
create index if not exists identity_links_contact_idx on ${links} (${l("contact")});
alter table ${links} enable row level security;
${revokeTable(links)}
grant select, delete on ${links} to authenticated;
grant all on ${links} to service_role;
drop policy if exists "identity_links_own_read" on ${links};
create policy "identity_links_own_read" on ${links} for select to authenticated
  using (${l("user")} = (select auth.uid()));
drop policy if exists "identity_links_own_delete" on ${links};
create policy "identity_links_own_delete" on ${links} for delete to authenticated
  using (${l("user")} = (select auth.uid()));

-- One-time link codes, stored as SHA-256. No policy: only the functions below read them.
create table if not exists ${codes} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("user")} uuid not null references auth.users (id) on delete cascade,
  ${c("kind")} text not null check (${c("kind")} in (${KINDS})),
  ${c("provider")} text check (length(${c("provider")}) between 1 and 100),
  ${c("codeHash")} text not null unique,
  ${c("expiresAt")} timestamptz not null,
  ${c("usedAt")} timestamptz,
  ${c("createdAt")} timestamptz not null default now()
);
create index if not exists identity_link_codes_user_idx on ${codes} (${c("user")});
${lockTable(codes)}

-- Issues a one-time code for the caller to hand to the bot or the mail
-- side. Issuing replaces the caller's unused codes for the same kind and
-- provider. Returns the code once.
create or replace function ${fn("begin_identity_link")}(kind text, provider text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := auth.uid();
  v_code text := upper(encode(extensions.gen_random_bytes(6), 'hex'));
  v_expires timestamptz := now() + interval '${String(minutes)} minutes';
begin
  if v_user is null then
    ${fail("IDENTITY_SIGN_IN_REQUIRED", "sign in to link an identity")}
  end if;
  if begin_identity_link.kind is null or begin_identity_link.kind not in (${KINDS}) then
    ${fail("IDENTITY_KIND", "kind must be email or chat", "22023")}
  end if;
  delete from ${codes}
  where ${c("user")} = v_user and ${c("kind")} = begin_identity_link.kind
    and ${c("provider")} is not distinct from begin_identity_link.provider
    and ${c("usedAt")} is null;
  insert into ${codes} (${c("user")}, ${c("kind")}, ${c("provider")}, ${c("codeHash")}, ${c("expiresAt")})
  values (v_user, begin_identity_link.kind, begin_identity_link.provider, ${sha256Hex("convert_to(v_code, 'utf8')")}, v_expires);
  return jsonb_build_object('code', v_code, 'expires_at', v_expires);
end;
$$;
${userGrant(`${fn("begin_identity_link")}(text, text)`)}

-- Binds the identity the bot or mail side saw to the user who issued the
-- code. A used, expired or unknown code, or an identity someone else holds,
-- is refused. Service role only: the caller vouches for the identity.
create or replace function ${fn("redeem_identity_link")}(code text, kind text, provider text, value text, workspace text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_code_id uuid;
  v_user uuid;
  v_value text := case when redeem_identity_link.kind = 'email' then lower(trim(redeem_identity_link.value)) else redeem_identity_link.value end;
  v_link ${links};
begin
  if redeem_identity_link.code is null or v_value is null or length(v_value) = 0 then
    ${fail("IDENTITY_LINK_INVALID", "invalid or expired link code", "22023")}
  end if;
  select ${c("id")}, ${c("user")} into v_code_id, v_user
  from ${codes}
  where ${c("codeHash")} = ${sha256Hex("convert_to(upper(regexp_replace(redeem_identity_link.code, '[^0-9A-Za-z]', '', 'g')), 'utf8')")}
    and ${c("kind")} = redeem_identity_link.kind
    and ${c("provider")} is not distinct from redeem_identity_link.provider
    and ${c("usedAt")} is null
    and ${c("expiresAt")} > now()
  for update;
  if not found then
    ${fail("IDENTITY_LINK_INVALID", "invalid or expired link code", "22023")}
  end if;
  update ${codes} set ${c("usedAt")} = now() where ${c("id")} = v_code_id;
  select * into v_link from ${links}
  where ${l("kind")} = redeem_identity_link.kind
    and ${l("provider")} is not distinct from redeem_identity_link.provider
    and ${l("value")} = v_value
    and ${l("workspace")} is not distinct from redeem_identity_link.workspace;
  if found then
    if v_link.${l("user")} is distinct from v_user then
      ${fail("IDENTITY_TAKEN", "this identity is linked to someone else", "23505")}
    end if;
  else
    insert into ${links} (${l("kind")}, ${l("provider")}, ${l("value")}, ${l("workspace")}, ${l("user")}, ${l("source")})
    values (redeem_identity_link.kind, redeem_identity_link.provider, v_value, redeem_identity_link.workspace, v_user, 'link')
    returning * into v_link;
  end if;
  return jsonb_build_object('id', v_link.${l("id")}, 'user_id', v_user);
end;
$$;
${serviceGrant(`${fn("redeem_identity_link")}(text, text, text, text, text)`)}

-- The link for an identity: {kind: 'user', userId} or {kind: 'contact',
-- contactId}, or null. An email address also matches a row stored without
-- a provider or workspace, such as a verified address.
create or replace function ${fn("principal_by_identity")}(kind text, provider text, value text, workspace text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when ${l("user")} is not null
    then jsonb_build_object('kind', 'user', 'userId', ${l("user")})
    else jsonb_build_object('kind', 'contact', 'contactId', ${l("contact")})
  end
  from ${links}
  where ${l("kind")} = principal_by_identity.kind
    and ${l("value")} = case when principal_by_identity.kind = 'email' then lower(trim(principal_by_identity.value)) else principal_by_identity.value end
    and (${l("provider")} is not distinct from principal_by_identity.provider or (${l("kind")} = 'email' and ${l("provider")} is null))
    and (${l("workspace")} is not distinct from principal_by_identity.workspace or (${l("kind")} = 'email' and ${l("workspace")} is null))
  order by ${l("provider")} is null, ${l("workspace")} is null
  limit 1
$$;
${serviceGrant(`${fn("principal_by_identity")}(text, text, text, text)`)}

-- Creates the email identity for a user whose address is confirmed. Does
-- nothing for an unconfirmed address or one that is already linked.
create or replace function ${fn("link_verified_email")}(user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_email text;
begin
  select lower(trim(u.email)) into v_email
  from auth.users u
  where u.id = link_verified_email.user_id and u.email_confirmed_at is not null and u.email is not null and length(trim(u.email)) > 0;
  if v_email is null then
    return false;
  end if;
  insert into ${links} (${l("kind")}, ${l("value")}, ${l("user")}, ${l("source")})
  values ('email', v_email, link_verified_email.user_id, 'verified_email')
  on conflict on constraint identity_links_identity_key do nothing;
  return found;
end;
$$;
${serviceGrant(`${fn("link_verified_email")}(uuid)`)}

-- Creates the email identities for users confirmed before the module was installed.
create or replace function ${fn("backfill_verified_emails")}()
returns integer
language sql
security definer
set search_path = ''
as $$
  select count(*)::integer from auth.users u
  where u.email_confirmed_at is not null and ${fn("link_verified_email")}(u.id)
$$;
${serviceGrant(`${fn("backfill_verified_emails")}()`)}

-- The caller's identities, through the read policy.
create or replace function ${fn("my_identities")}()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', ${l("id")}, 'kind', ${l("kind")}, 'provider', ${l("provider")}, 'value', ${l("value")},
    'workspace', ${l("workspace")}, 'source', ${l("source")}, 'created_at', ${l("createdAt")}
  ) order by ${l("createdAt")}), '[]'::jsonb)
  from ${links}
  where ${l("user")} = (select auth.uid())
$$;
${userGrant(`${fn("my_identities")}()`)}

-- Removes one of the caller's identities, through the delete policy.
create or replace function ${fn("unlink_identity")}(id uuid)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
#variable_conflict use_column
begin
  delete from ${links} where ${l("id")} = unlink_identity.id and ${l("user")} = (select auth.uid());
  return found;
end;
$$;
${userGrant(`${fn("unlink_identity")}(uuid)`)}
${emailTrigger}
`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "begin_identity_link", args: ["text", "text"], returns: "jsonb" },
    {
      name: "redeem_identity_link",
      args: ["text", "text", "text", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "principal_by_identity",
      args: ["text", "text", "text", "text"],
      returns: "jsonb",
    },
    { name: "link_verified_email", args: ["uuid"], returns: "boolean" },
    { name: "backfill_verified_emails", args: [], returns: "integer" },
    { name: "my_identities", args: [], returns: "jsonb" },
    { name: "unlink_identity", args: ["uuid"], returns: "boolean" },
  ];
}

export const IDENTITIES: BlockSqlDefinition = {
  name: "identities",
  title: "Identities",
  description:
    "Links an email address or a chat user to an app user or a contact. Rows come only from a one-time code the signed-in user issues and the service redeems, or from a confirmed address in auth.users.",
  requires: [],
  integrates: ["inbox"],
  target: "schema",
  version: 1,
  names: NAMES,
  contract,
  build,
};
