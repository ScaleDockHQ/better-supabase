import type { FieldEncryptionEvents } from "../../blocks/field-encryption/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import {
  fail,
  schemaPreamble,
  SERVICE_CALLER,
  serviceGrant,
} from "../shared.ts";

const EVENTS: BlockSqlEvents<FieldEncryptionEvents> = {
  "field_key.dropped": { subject: "field-keys", payload: ["owner"] },
};

const NAMES: BlockSqlNames = { events: EVENTS, tables: {} };

/** The prefix of every ciphertext the module writes: format 1. */
export const FIELD_CIPHER_PREFIX = "bsf1:";

/** The Vault secret name prefix of a data key; the owner follows it. */
const FIELD_KEY_PREFIX = "bs:field-key:";

/** The Vault secret name prefix of a lookup key; the owner follows it. */
const FIELD_LOOKUP_KEY_PREFIX = "bs:field-lookup-key:";

/** The pgcrypto options: AES-256, and one S2K pass since the key is random. */
const CIPHER_OPTIONS = "cipher-algo=aes256, s2k-mode=1";

/** SQL that revokes a function from every API role, the service role too. */
const privateGrant = (signature: string): string =>
  `revoke execute on function ${signature} from public, anon, authenticated, service_role;`;

/** The SQL that owner `expression` names a data key by: `tenant:<id>` and so on. */
export function fieldKeyOwner(
  kind: "tenant" | "user" | "none",
  column: string,
): string {
  switch (kind) {
    case "tenant": {
      return `'tenant:' || (${column})::text`;
    }

    case "user": {
      return `'user:' || (${column})::text`;
    }

    case "none": {
      return "'app'";
    }

    default: {
      const never: never = kind;

      return never;
    }
  }
}

function build(ctx: BlockSqlContext): string {
  const fn = (name: string): string => ctx.fn(name);

  const secret = (owner: string, prefix = FIELD_KEY_PREFIX): string =>
    `'${prefix}' || ${owner}`;

  // The key of an owner from Vault, created on first use when `make` is true.
  const keyFunction = (name: string, prefix: string, label: string): string => {
    const owner = `${name}.owner`;

    return `create or replace function ${fn(name)}(owner text, make boolean default true)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text;
begin
  if ${owner} is null or length(${owner}) = 0 then
    ${fail("FIELD_KEY_OWNER", "a field key needs an owner", "22023")}
  end if;
  select ds.decrypted_secret into v_key from vault.decrypted_secrets ds
  where ds.name = ${secret(owner, prefix)};
  if v_key is not null or not ${name}.make then
    return v_key;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(${secret(owner, prefix)}, 0));
  select ds.decrypted_secret into v_key from vault.decrypted_secrets ds
  where ds.name = ${secret(owner, prefix)};
  if v_key is null then
    v_key := encode(extensions.gen_random_bytes(32), 'base64');
    perform vault.create_secret(v_key, ${secret(owner, prefix)}, '${label}');
  end if;
  return v_key;
end;
$$;
${privateGrant(`${fn(name)}(text, boolean)`)}`;
  };

  return `${schemaPreamble(ctx)}
create extension if not exists pgcrypto with schema extensions;

-- Field data keys live only in Vault, one per owner (tenant:<id>, user:<id>
-- or app), as bs:field-key:<owner>, and the lookup keys next to them as
-- bs:field-lookup-key:<owner>. No API role calls field_key, field_lookup_key,
-- field_seal, field_open or field_hash; security definer functions of app
-- tables and custom fields do, after they check the caller's scope.
${keyFunction("field_key", FIELD_KEY_PREFIX, "better-supabase field encryption key")}

${keyFunction("field_lookup_key", FIELD_LOOKUP_KEY_PREFIX, "better-supabase field lookup key")}

-- Encrypts a value with a data key: ${FIELD_CIPHER_PREFIX} then base64 of an OpenPGP message.
create or replace function ${fn("field_seal")}(key text, value text)
returns text
language sql
volatile
set search_path = ''
as $$
  select case when field_seal.value is null then null
    else '${FIELD_CIPHER_PREFIX}' || translate(encode(extensions.pgp_sym_encrypt(field_seal.value, field_seal.key, '${CIPHER_OPTIONS}'), 'base64'), E'\\n', '')
  end
$$;
${privateGrant(`${fn("field_seal")}(text, text)`)}

-- Decrypts a value; a value without the prefix was stored before the column
-- was encrypted and comes back as it is. null when the key is gone.
create or replace function ${fn("field_open")}(key text, value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when field_open.value is null then null
    when left(field_open.value, ${String(FIELD_CIPHER_PREFIX.length)}) <> '${FIELD_CIPHER_PREFIX}' then field_open.value
    when field_open.key is null then null
    else extensions.pgp_sym_decrypt(decode(substr(field_open.value, ${String(FIELD_CIPHER_PREFIX.length + 1)}), 'base64'), field_open.key)
  end
$$;
${privateGrant(`${fn("field_open")}(text, text)`)}

-- The lookup hash of a value: HMAC-SHA256 of the value, lowercased and
-- without whitespace, under a lookup key. null without a key or a value.
create or replace function ${fn("field_hash")}(key text, value text)
returns bytea
language sql
immutable
set search_path = ''
as $$
  select case when field_hash.key is null or field_hash.value is null then null
    else extensions.hmac(convert_to(lower(regexp_replace(field_hash.value, '\\s', '', 'g')), 'UTF8'), decode(field_hash.key, 'base64'), 'sha256')
  end
$$;
${privateGrant(`${fn("field_hash")}(text, text)`)}

-- Encrypts a value with the owner's key, creating the key on first use.
create or replace function ${fn("field_encrypt")}(owner text, value text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  if field_encrypt.value is null then
    return null;
  end if;
  return ${fn("field_seal")}(${fn("field_key")}(field_encrypt.owner, true), field_encrypt.value);
end;
$$;
${serviceGrant(`${fn("field_encrypt")}(text, text)`)}

-- Decrypts a value with the owner's key; null when the key was dropped.
create or replace function ${fn("field_decrypt")}(owner text, value text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  if field_decrypt.value is null then
    return null;
  end if;
  return ${fn("field_open")}(${fn("field_key")}(field_decrypt.owner, false), field_decrypt.value);
end;
$$;
${serviceGrant(`${fn("field_decrypt")}(text, text)`)}

-- The lookup hash of a value under the owner's lookup key, to compare with a
-- <column>_lookup column; null when the owner has no lookup key.
create or replace function ${fn("field_lookup")}(owner text, value text)
returns bytea
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if field_lookup.value is null then
    return null;
  end if;
  return ${fn("field_hash")}(${fn("field_lookup_key")}(field_lookup.owner, false), field_lookup.value);
end;
$$;
${serviceGrant(`${fn("field_lookup")}(text, text)`)}

-- Deletes an owner's data key and lookup key, so every value encrypted with
-- them reads as null and no lookup finds it (crypto-shredding, for example
-- after a tenant is erased).
create or replace function ${fn("drop_field_key")}(owner text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (${SERVICE_CALLER}) then
    ${fail("FIELD_KEY_FORBIDDEN", "only the service role drops field keys")}
  end if;
  delete from vault.secrets s where s.name in (${secret("drop_field_key.owner")}, ${secret("drop_field_key.owner", FIELD_LOOKUP_KEY_PREFIX)});
  if not found then
    return false;
  end if;
  ${ctx.record({
    type: "field_key.dropped",
    payload: "jsonb_build_object('owner', drop_field_key.owner)",
    subject: "'field-keys/' || drop_field_key.owner",
    audit: {
      category: "security",
      targetType: "field_key",
      recordId: "drop_field_key.owner",
    },
  })}
  return true;
end;
$$;
${serviceGrant(`${fn("drop_field_key")}(text)`)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "field_encrypt", args: ["text", "text"], returns: "text" },
    { name: "field_decrypt", args: ["text", "text"], returns: "text" },
    { name: "field_lookup", args: ["text", "text"], returns: "bytea" },
    { name: "drop_field_key", args: ["text"], returns: "boolean" },
  ];
}

export const FIELD_ENCRYPTION: BlockSqlDefinition = {
  name: "field-encryption",
  title: "Field encryption",
  description:
    "Encrypts app table columns and custom field values at rest with a data key per tenant, user or app, kept in Supabase Vault as bs:field-key:<owner>. Only security definer read paths that check the caller's scope decrypt; a lookup column keeps an HMAC of the value under the owner's lookup key for equality searches; drop_field_key deletes both keys so the values can no longer be read or found.",
  requires: [],
  target: "schema",
  modes: ["managed"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
