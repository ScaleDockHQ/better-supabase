import type { SigningKeysEvents } from "../../blocks/signing-keys/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import {
  fail,
  lockTable,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
} from "../shared.ts";

const EVENTS: BlockSqlEvents<SigningKeysEvents> = {
  "signing_key.created": {
    subject: "signing-keys",
    payload: ["ownerType", "ownerId", "kid", "alg"],
  },
  "signing_key.retired": {
    subject: "signing-keys",
    payload: ["ownerType", "ownerId", "kid"],
  },
};

const NAMES: BlockSqlNames = {
  events: EVENTS,
  options: ["jwksGrace"],
  tables: {
    keys: {
      name: "signing_keys",
      columns: {
        id: "id",
        ownerType: "owner_type",
        ownerId: "owner_id",
        kid: "kid",
        alg: "alg",
        publicJwk: "public_jwk",
        vaultId: "vault_secret_id",
        state: "state",
        publishUntil: "publish_until",
        createdAt: "created_at",
        retiredAt: "retired_at",
      },
      app: {},
      optional: ["createdAt", "retiredAt"],
      typed: ["alg", "state"],
    },
  },
};

const guard = `
  if not (${SERVICE_CALLER}) then
    ${fail("SIGNING_KEYS_FORBIDDEN", "only the service role manages signing keys")}
  end if;`;

function keyEvent(
  ctx: BlockSqlContext,
  type: "signing_key.created" | "signing_key.retired",
  row: string,
): string {
  const k = (logical: string): string => `${row}.${ctx.col("keys", logical)}`;

  return ctx.record({
    type,
    payload: `jsonb_build_object('ownerType', ${k("ownerType")}, 'ownerId', ${k("ownerId")}, 'kid', ${k("kid")}${
      type === "signing_key.created" ? `, 'alg', ${k("alg")}` : ""
    })`,
    subject: `'signing-keys/' || ${k("kid")}`,
    audit: {
      category: "security",
      targetType: "signing_key",
      recordId: k("kid"),
    },
  });
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const t = ctx.table("keys");
  const c = (logical: string): string => ctx.col("keys", logical);
  const fn = (name: string): string => ctx.fn(name);
  const grace = ctx.text("jwksGrace", "5 minutes");
  const created = ctx.has("keys", "createdAt");

  const retire = `${c("state")} = ${ctx.cast("keys", "state", "'retired'")}${
    ctx.has("keys", "retiredAt") ? `, ${c("retiredAt")} = now()` : ""
  }`;

  const published = (alias: string): string =>
    `(${alias}.${c("state")} = 'active' or ${alias}.${c("publishUntil")} + coalesce(grace, ${sqlString(grace)}::interval) > now())`;

  return `${schemaPreamble(ctx)}
-- Asymmetric signing keys per owner (a tenant, an app, a stream): the public
-- JWK here, the private JWK in Vault. One key per owner is active; a retired
-- key stays in the JWKS until publish_until, the latest exp a signer noted.
create table if not exists ${t} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("ownerType")} text not null check (${c("ownerType")} ~ '^[a-z][a-z0-9_-]{0,39}$'),
  ${c("ownerId")} text not null check (length(${c("ownerId")}) between 1 and 200),
  ${c("kid")} text not null unique check (length(${c("kid")}) between 1 and 200),
  ${c("alg")} text not null check (${c("alg")} in ('Ed25519', 'ES256')),
  ${c("publicJwk")} jsonb not null check (not (${c("publicJwk")} ? 'd')),
  ${c("vaultId")} uuid not null,
  ${c("state")} text not null default 'active' check (${c("state")} in ('active', 'retired')),
  ${c("publishUntil")} timestamptz${created ? `,\n  ${c("createdAt")} timestamptz not null default now()` : ""}${ctx.has("keys", "retiredAt") ? `,\n  ${c("retiredAt")} timestamptz` : ""}
);
create unique index if not exists signing_keys_active_idx on ${t} (${c("ownerType")}, ${c("ownerId")}) where ${c("state")} = 'active';
create index if not exists signing_keys_owner_idx on ${t} (${c("ownerType")}, ${c("ownerId")}${created ? `, ${c("createdAt")} desc` : ""});
${lockTable(t)}

-- Adds a key and makes it the owner's active one; the key it replaces is
-- retired and stays published until its last token expires.
create or replace function ${fn("add_signing_key")}(owner_type text, owner_id text, kid text, alg text, public_jwk jsonb, private_jwk text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old ${t};
  v_row ${t};
  v_vault uuid;
begin${guard}
  if add_signing_key.private_jwk is null or length(add_signing_key.private_jwk) = 0 then
    ${fail("SIGNING_KEY_INVALID", "a signing key needs its private JWK", "22023")}
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'bs:signing:' || add_signing_key.owner_type || ':' || add_signing_key.owner_id, 0));
  update ${t} k set ${retire}
  where k.${c("ownerType")} = add_signing_key.owner_type
    and k.${c("ownerId")} = add_signing_key.owner_id
    and k.${c("state")} = 'active'
  returning k.* into v_old;
  v_vault := vault.create_secret(
    add_signing_key.private_jwk,
    'bs:signing:' || add_signing_key.kid,
    'better-supabase signing key'
  );
  insert into ${t} (${c("ownerType")}, ${c("ownerId")}, ${c("kid")}, ${c("alg")}, ${c("publicJwk")}, ${c("vaultId")})
  values (add_signing_key.owner_type, add_signing_key.owner_id, add_signing_key.kid, ${ctx.cast("keys", "alg", "add_signing_key.alg")},
    add_signing_key.public_jwk, v_vault)
  returning * into v_row;
  if v_old.${c("kid")} is not null then
    ${keyEvent(ctx, "signing_key.retired", "v_old")}
  end if;
  ${keyEvent(ctx, "signing_key.created", "v_row")}
  return jsonb_build_object('kid', v_row.${c("kid")}, 'alg', v_row.${c("alg")}, 'retired', v_old.${c("kid")});
end;
$$;
${serviceGrant(`${fn("add_signing_key")}(text, text, text, text, jsonb, text)`)}

-- The owner's active key with its private JWK, or null.
create or replace function ${fn("signing_key")}(owner_type text, owner_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin${guard}
  return (
    select jsonb_build_object('kid', k.${c("kid")}, 'alg', k.${c("alg")}, 'privateKey', ds.decrypted_secret)
    from ${t} k
    join vault.decrypted_secrets ds on ds.id = k.${c("vaultId")}
    where k.${c("ownerType")} = signing_key.owner_type
      and k.${c("ownerId")} = signing_key.owner_id
      and k.${c("state")} = 'active'
  );
end;
$$;
${serviceGrant(`${fn("signing_key")}(text, text)`)}

-- Keeps the key published until at least exp; false for an unknown kid.
create or replace function ${fn("note_signing_key_exp")}(kid text, exp timestamptz)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin${guard}
  update ${t} k set ${c("publishUntil")} = note_signing_key_exp.exp
  where k.${c("kid")} = note_signing_key_exp.kid
    and (k.${c("publishUntil")} is null or k.${c("publishUntil")} < note_signing_key_exp.exp);
  return exists (select 1 from ${t} k where k.${c("kid")} = note_signing_key_exp.kid);
end;
$$;
${serviceGrant(`${fn("note_signing_key_exp")}(text, timestamptz)`)}

-- Retires a key without a replacement; false when it was not active.
create or replace function ${fn("retire_signing_key")}(kid text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t};
begin${guard}
  update ${t} k set ${retire}
  where k.${c("kid")} = retire_signing_key.kid and k.${c("state")} = 'active'
  returning k.* into v_row;
  if v_row.${c("kid")} is null then
    return false;
  end if;
  ${keyEvent(ctx, "signing_key.retired", "v_row")}
  return true;
end;
$$;
${serviceGrant(`${fn("retire_signing_key")}(text)`)}

-- The owner's JWK Set: the active key and every retired key still in use.
create or replace function ${fn("signing_jwks")}(owner_type text, owner_id text, grace interval default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin${guard}
  return jsonb_build_object('keys', coalesce((
    select jsonb_agg(k.${c("publicJwk")} || jsonb_build_object('kid', k.${c("kid")}, 'use', 'sig')${
      created ? `\n      order by k.${c("createdAt")} desc` : ""
    })
    from ${t} k
    where k.${c("ownerType")} = signing_jwks.owner_type
      and k.${c("ownerId")} = signing_jwks.owner_id
      and ${published("k")}
  ), '[]'::jsonb));
end;
$$;
${serviceGrant(`${fn("signing_jwks")}(text, text, interval)`)}

-- Deletes every key of an owner, for example from on_organization_purge.
create or replace function ${fn("delete_signing_keys")}(owner_type text, owner_id text)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin${guard}
  delete from ${t} k
  where k.${c("ownerType")} = delete_signing_keys.owner_type
    and k.${c("ownerId")} = delete_signing_keys.owner_id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${serviceGrant(`${fn("delete_signing_keys")}(text, text)`)}

-- Deletes retired keys no token can still need.
create or replace function ${fn("purge_signing_keys")}(grace interval default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin${guard}
  delete from ${t} k
  where k.${c("state")} = 'retired' and not ${published("k")};
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${serviceGrant(`${fn("purge_signing_keys")}(interval)`)}

-- Deleting a key deletes its Vault secret.
create or replace function ${fn("drop_signing_key_vault_secret")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from vault.secrets vs where vs.id = old.${c("vaultId")};
  return null;
end;
$$;
revoke execute on function ${fn("drop_signing_key_vault_secret")}() from public, anon, authenticated;
drop trigger if exists ${ctx.trigger("signing_key_vault")} on ${t};
create trigger ${ctx.trigger("signing_key_vault")} after delete on ${t}
  for each row execute function ${fn("drop_signing_key_vault_secret")}();`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "add_signing_key",
      args: ["text", "text", "text", "text", "jsonb", "text"],
      returns: "jsonb",
    },
    { name: "signing_key", args: ["text", "text"], returns: "jsonb" },
    {
      name: "note_signing_key_exp",
      args: ["text", "timestamptz"],
      returns: "boolean",
    },
    { name: "retire_signing_key", args: ["text"], returns: "boolean" },
    {
      name: "signing_jwks",
      args: ["text", "text", "interval"],
      returns: "jsonb",
    },
    { name: "delete_signing_keys", args: ["text", "text"], returns: "integer" },
    { name: "purge_signing_keys", args: ["interval"], returns: "integer" },
  ];
}

export const SIGNING_KEYS: BlockSqlDefinition = {
  name: "signing-keys",
  title: "Signing keys",
  description:
    "Ed25519 or ES256 signing keys per owner: the private JWK in Supabase Vault, one active key per owner, rotation that keeps a retired kid in the JWKS until the latest exp a signer noted, and a purge. Only the service role calls it; createSigningKeys() in better-supabase/blocks/signing-keys generates keys and signs with WebCrypto.",
  requires: [],
  integrates: ["outbox", "audit"],
  target: "schema",
  version: 1,
  names: NAMES,
  contract,
  build,
};
