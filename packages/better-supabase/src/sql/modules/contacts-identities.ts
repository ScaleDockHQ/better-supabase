import type { BlockSqlContext } from "../context.ts";
import type { PartyNames } from "./contacts-functions.ts";

import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { fail, userGrant } from "../shared.ts";
import { appUniqueIndex, lockModuleTable } from "./over-app.ts";

/** What a person's email must look like, as the people table checks it. */
export const EMAIL_PATTERN = "'^[^@[:space:]]+@[^@[:space:]]+$'";

/**
 * The people columns contacts 0.47 added for the inbox, as `alter table`s an
 * upgrade runs before the module file.
 */
export function peopleInboxColumns(ctx: BlockSqlContext): string {
  const t = ctx.table("people");

  const column = (logical: string, definition: string): string =>
    ctx.has("people", logical)
      ? `\nalter table ${t} add column if not exists ${ctx.col("people", logical)} ${definition};`
      : "";

  return `${column("avatarUrl", "text")}${column("metadata", "jsonb not null default '{}'::jsonb")}`;
}

/**
 * The person_identities table: the addresses a person has on a channel (an
 * email address, a WhatsApp number). One address on a channel belongs to one
 * person of an organization.
 */
export function identitiesTable(
  ctx: BlockSqlContext,
  names: PartyNames,
): string {
  if (!ctx.manages) {
    return "";
  }

  const { t, c } = names;
  const ic = (column: string): string => c("identities", column);
  const pe = (column: string): string => c("people", column);

  const optional = (logical: string, definition: string): string =>
    ctx.has("identities", logical) ? `\n  ${ic(logical)} ${definition},` : "";

  return `
create table if not exists ${t("identities")} (
  ${ic("id")} uuid primary key default gen_random_uuid(),
  ${ic("tenant")} ${ctx.idType} not null,
  ${ic("person")} uuid not null references ${t("people")} (${pe("id")}) on delete cascade,
  ${ic("channel")} text not null check (length(${ic("channel")}) between 1 and 50),
  ${ic("address")} text not null check (length(${ic("address")}) between 1 and 500),${optional("verifiedAt", "timestamptz")}${optional("createdAt", "timestamptz not null default now()")}
  unique (${ic("tenant")}, ${ic("channel")}, ${ic("address")})
);${appUniqueIndex(ctx, "identities", ["tenant", "channel", "address"])}
create index if not exists ${ctx.naming.rename("person_identities_person_idx")} on ${t("identities")} (${ic("person")});
${lockModuleTable(ctx, "identities", { read: true })}
${renderPolicy(makePolicy({ table: t("identities"), name: `${ctx.tableName("identities").name}_read`, command: "select", roles: ["authenticated"], using: ctx.scope.check(ic("tenant"), names.read) }), { drop: true, target: t("identities") })}
`;
}

/**
 * `resolve_person` and the identity calls: list, add and remove a person's
 * identities, and find the person an address belongs to.
 */
export function identityFunctions(
  ctx: BlockSqlContext,
  names: PartyNames,
): string {
  const { t, c, fn } = names;
  const ic = (column: string): string => c("identities", column);
  const pe = (column: string): string => c("people", column);
  const has = (logical: string): boolean => ctx.has("people", logical);
  const verified = ctx.has("identities", "verifiedAt");

  // An identity under fixed keys, whatever the app names its columns.
  const json = (alias: string): string =>
    `jsonb_build_object('id', ${alias}.${ic("id")}, 'tenant_id', ${alias}.${ic("tenant")}, 'person_id', ${alias}.${ic("person")}, 'channel', ${alias}.${ic("channel")}, 'address', ${alias}.${ic("address")}, 'verified_at', ${verified ? `${alias}.${ic("verifiedAt")}` : "null"}, 'created_at', ${ctx.has("identities", "createdAt") ? `${alias}.${ic("createdAt")}` : "null"})`;

  const guard = (
    tenant: string,
  ): string => `if not (auth.role() = 'service_role' or ${ctx.scope.can(tenant, names.write)}) then
    ${fail("PARTY_FORBIDDEN", "not allowed to change companies and people")}
  end if;`;

  const text = (key: string): string => `nullif(trim(input ->> '${key}'), '')`;

  const metadata = `case when jsonb_typeof(input -> 'metadata') = 'object' then input -> 'metadata' else '{}'::jsonb end`;

  const created: (readonly [string, string])[] = [
    ["tenant", "resolve_person.tenant"],
    ["name", "v_name"],
    ["email", "v_email"],
    ["phone", text("phone")],
    [
      "lifecycle",
      ctx.cast("people", "lifecycle", `(${names.personStages})[1]`),
    ],
    ["user", `${text("user_id")}::uuid`],
    ...(has("avatarUrl") ? [["avatarUrl", text("avatar_url")] as const] : []),
    ...(has("metadata")
      ? [
          [
            "metadata",
            `${metadata} || case when v_email is null and ${text("email")} is not null then jsonb_build_object('email', ${text("email")}) else '{}'::jsonb end`,
          ] as const,
        ]
      : []),
    ...(has("createdBy") ? [["createdBy", "auth.uid()"] as const] : []),
  ];

  // What a match takes from the input: only what the person lacks, except
  // the avatar, which follows the channel, and metadata, which merges.
  const filled: (readonly [string, string])[] = [
    [
      "email",
      `coalesce(p.${pe("email")}, case when not exists (select 1 from ${t("people")} o where o.${pe("tenant")} = p.${pe("tenant")} and o.${pe("email")} = v_email and o.${pe("archivedAt")} is null and o.${pe("id")} <> p.${pe("id")}) then v_email end)`,
    ],
    ["phone", `coalesce(p.${pe("phone")}, ${text("phone")})`],
    ["user", `coalesce(p.${pe("user")}, ${text("user_id")}::uuid)`],
    ...(has("avatarUrl")
      ? [
          [
            "avatarUrl",
            `coalesce(${text("avatar_url")}, p.${pe("avatarUrl")})`,
          ] as const,
        ]
      : []),
    ...(has("metadata")
      ? [["metadata", `p.${pe("metadata")} || ${metadata}`] as const]
      : []),
  ];

  const createdRecord = ctx.record({
    type: "person.created",
    payload: `jsonb_build_object('organizationId', resolve_person.tenant, 'personId', v_person, 'name', v_name)`,
    subject: `'persons/' || v_person::text`,
    tenant: "resolve_person.tenant::text",
    audit: false,
  });

  return `
-- The person contact fields name, for the inbox and the channels: by id,
-- then by the identity on a channel ({ channel, address }), the user, then
-- the email. Fills in what the person lacks, or creates a lead; an identity
-- is attached when given. A merged person resolves to the one it was merged
-- into. No permission check: callers check.
create or replace function ${fn("resolve_person")}(tenant ${ctx.idType}, input jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_person uuid;
  v_identity jsonb := input -> 'identity';
  v_channel text := nullif(trim(v_identity ->> 'channel'), '');
  v_address text := nullif(trim(coalesce(v_identity ->> 'address', v_identity ->> 'external_id')), '');
  v_email text := lower(nullif(trim(input ->> 'email'), ''));
  v_name text;
begin
  if v_email !~ ${EMAIL_PATTERN} then
    v_email := null;
  end if;
  if ${text("id")} is not null then
    select p.${pe("id")} into v_person from ${t("people")} p
    where p.${pe("id")} = ${text("id")}::uuid and p.${pe("tenant")} = resolve_person.tenant;
    if v_person is null then
      ${fail("CONTACT_NOT_FOUND", "contact not found", "P0002")}
    end if;
  end if;
  if v_person is null and v_channel is not null and v_address is not null then
    select i.${ic("person")} into v_person from ${t("identities")} i
    where i.${ic("tenant")} = resolve_person.tenant and i.${ic("channel")} = v_channel and i.${ic("address")} = v_address;
  end if;
  if v_person is null and ${text("user_id")} is not null then
    select p.${pe("id")} into v_person from ${t("people")} p
    where p.${pe("tenant")} = resolve_person.tenant and p.${pe("user")} = ${text("user_id")}::uuid
    order by p.${pe("archivedAt")} nulls first, p.${pe("createdAt")}, p.${pe("id")} limit 1;
  end if;
  if v_person is null and v_email is not null then
    select p.${pe("id")} into v_person from ${t("people")} p
    where p.${pe("tenant")} = resolve_person.tenant and p.${pe("email")} = v_email and p.${pe("archivedAt")} is null;
  end if;
  if v_person is not null then
    select coalesce(p.${pe("mergedInto")}, p.${pe("id")}) into v_person from ${t("people")} p where p.${pe("id")} = v_person;
    update ${t("people")} p set
      ${filled.map(([column, value]) => `${pe(column)} = ${value}`).join(",\n      ")},
      ${pe("updatedAt")} = now()
    where p.${pe("id")} = v_person
      and (${filled.map(([column]) => `p.${pe(column)}`).join(", ")}) is distinct from (${filled.map(([, value]) => value).join(", ")});
  else
    v_name := left(coalesce(${text("name")}, v_email, ${text("phone")}, v_address, 'Unknown contact'), 300);
    begin
      insert into ${t("people")} (${created.map(([column]) => pe(column)).join(", ")})
      values (${created.map(([, value]) => value).join(", ")})
      returning ${pe("id")} into v_person;
      ${createdRecord}
    exception when unique_violation then
      select p.${pe("id")} into v_person from ${t("people")} p
      where p.${pe("tenant")} = resolve_person.tenant and p.${pe("email")} = v_email and p.${pe("archivedAt")} is null;
      if v_person is null then
        raise;
      end if;
    end;
  end if;
  if v_channel is not null and v_address is not null then
    insert into ${t("identities")} (${ic("tenant")}, ${ic("person")}, ${ic("channel")}, ${ic("address")})
    values (resolve_person.tenant, v_person, v_channel, v_address)
    on conflict do nothing;
  end if;
  return v_person;
end;
$$;
revoke execute on function ${fn("resolve_person")}(${ctx.idType}, jsonb) from public, anon, authenticated;

-- A person's identities, by channel and address.
create or replace function ${fn("list_person_identities")}(person uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${json("i")} order by i.${ic("channel")}, i.${ic("address")}), '[]'::jsonb)
  from ${t("identities")} i where i.${ic("person")} = list_person_identities.person
$$;
${userGrant(`${fn("list_person_identities")}(uuid)`)}

-- Adds an address on a channel to a person, or marks it verified. An address
-- another person of the organization holds is refused.
create or replace function ${fn("add_person_identity")}(person uuid, channel text, address text, verified boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_channel text := nullif(trim(add_person_identity.channel), '');
  v_address text := nullif(trim(add_person_identity.address), '');
  v_holder uuid;
  v_row jsonb;
begin
  select p.${pe("tenant")} into v_tenant from ${t("people")} p
  where p.${pe("id")} = add_person_identity.person and p.${pe("mergedInto")} is null;
  if v_tenant is null then
    ${fail("PARTY_NOT_FOUND", "person not found", "P0002")}
  end if;
  ${guard("v_tenant")}
  if v_channel is null or v_address is null then
    ${fail("PARTY_IDENTITY_INVALID", "an identity needs a channel and an address", "22023")}
  end if;
  select i.${ic("person")} into v_holder from ${t("identities")} i
  where i.${ic("tenant")} = v_tenant and i.${ic("channel")} = v_channel and i.${ic("address")} = v_address;
  if v_holder is not null and v_holder <> add_person_identity.person then
    ${fail("PARTY_IDENTITY_TAKEN", "another person has this address", "23505")}
  end if;
  insert into ${t("identities")} (${ic("tenant")}, ${ic("person")}, ${ic("channel")}, ${ic("address")}${verified ? `, ${ic("verifiedAt")}` : ""})
  values (v_tenant, add_person_identity.person, v_channel, v_address${verified ? ", case when add_person_identity.verified then now() end" : ""})
  on conflict do nothing;${
    verified
      ? `
  if add_person_identity.verified then
    update ${t("identities")} i set ${ic("verifiedAt")} = coalesce(i.${ic("verifiedAt")}, now())
    where i.${ic("tenant")} = v_tenant and i.${ic("channel")} = v_channel and i.${ic("address")} = v_address;
  end if;`
      : ""
  }
  select ${json("i")} into v_row from ${t("identities")} i
  where i.${ic("tenant")} = v_tenant and i.${ic("channel")} = v_channel and i.${ic("address")} = v_address;
  return v_row;
end;
$$;
${userGrant(`${fn("add_person_identity")}(uuid, text, text, boolean)`)}

create or replace function ${fn("remove_person_identity")}(identity uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select i.${ic("tenant")} into v_tenant from ${t("identities")} i where i.${ic("id")} = remove_person_identity.identity;
  if v_tenant is null then
    return false;
  end if;
  ${guard("v_tenant")}
  delete from ${t("identities")} i where i.${ic("id")} = remove_person_identity.identity;
  return true;
end;
$$;
${userGrant(`${fn("remove_person_identity")}(uuid)`)}

-- The person an address on a channel belongs to, or null.
create or replace function ${fn("find_person_by_identity")}(tenant ${ctx.idType}, channel text, address text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(p) from ${t("identities")} i
  join ${t("people")} p on p.${pe("id")} = i.${ic("person")}
  where i.${ic("tenant")} = find_person_by_identity.tenant
    and i.${ic("channel")} = trim(find_person_by_identity.channel)
    and i.${ic("address")} = trim(find_person_by_identity.address)
$$;
${userGrant(`${fn("find_person_by_identity")}(${ctx.idType}, text, text)`)}
`;
}

/** SQL for a person merge: the dropped person's identities move to the kept one. */
export function identityMergeMoves(
  names: PartyNames,
  keep: string,
  drop: string,
): string {
  const ic = (column: string): string => names.c("identities", column);

  return `\n  update ${names.t("identities")} i set ${ic("person")} = ${keep} where i.${ic("person")} = ${drop};`;
}
