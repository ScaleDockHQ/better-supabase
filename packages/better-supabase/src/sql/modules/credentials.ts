import type { CredentialsEvents } from "../../blocks/credentials/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import { schemaPreamble, SERVICE_CALLER, serviceGrant } from "../shared.ts";

const EVENTS: BlockSqlEvents<CredentialsEvents> = {
  "credential.set": { subject: "credentials", payload: ["provider", "name"] },
  "credential.deleted": {
    subject: "credentials",
    payload: ["provider", "name"],
  },
};

const NAMES: BlockSqlNames = {
  tables: {
    secrets: {
      name: "credentials",
      columns: {
        provider: "provider",
        name: "name",
        tenant: "tenant",
        scope: "scope",
        vaultId: "vault_id",
        secret: "secret",
        updatedAt: "updated_at",
      },
      optional: ["tenant", "scope", "vaultId", "secret", "updatedAt"],
    },
  },
  options: ["secretStorage"],
  events: EVENTS,
};

/**
 * True when the credential_ref `ref` doesn't carry `"tenant": <tenant>`, the
 * SQL side of `credentialRefInTenant`.
 */
export function refOutsideTenant(ref: string, tenant: string): string {
  return `jsonb_typeof(${ref} -> 'tenant') is distinct from 'string' or (${ref} ->> 'tenant') is distinct from (${tenant})::text`;
}

/**
 * PL/pgSQL that rejects a credential_ref outside `tenant` unless the service
 * role calls: a tenant admin's ref must carry `"tenant": <tenant>`, so a
 * provider resolves it only inside that tenant's namespace.
 */
export function tenantRefGuard(ref: string, tenant: string): string {
  return `if not (${SERVICE_CALLER}) and ${ref} is not null and jsonb_typeof(${ref}) <> 'null'
    and (${refOutsideTenant(ref, tenant)}) then
    raise exception 'credential_ref must carry the tenant % that owns it', ${tenant}
      using errcode = '42501', hint = 'CREDENTIAL_REF_FOREIGN';
  end if;`;
}

const guard = (name: string): string => `
  if not (${SERVICE_CALLER}) then
    raise exception 'only the service role reads and writes credentials'
      using errcode = '42501', hint = 'CREDENTIALS_FORBIDDEN';
  end if;
  if ${name}.provider !~ '^[a-z][a-z0-9-]{0,39}$' or ${name}.name !~ '^[A-Za-z0-9][A-Za-z0-9:._/@-]{0,199}$' then
    raise exception 'credential names are a provider and a name of letters, digits and :._/@-'
      using errcode = 'P0001', hint = 'CREDENTIAL_NAME_INVALID';
  end if;`;

const secretName = (name: string): string =>
  `'bs:cred:' || ${name}.provider || ':' || ${name}.name`;

function credentialEvent(
  ctx: BlockSqlContext,
  type: string,
  name: string,
): string {
  return ctx.record({
    type,
    payload: `jsonb_build_object('provider', ${name}.provider, 'name', ${name}.name)`,
    subject: `'credentials/' || ${name}.provider || '/' || ${name}.name`,
    audit: {
      category: "security",
      targetType: "credential",
      recordId: `${name}.provider || ':' || ${name}.name`,
    },
  });
}

/** Whether an adopted table keeps secrets in Vault (`vaultId`) or in a column. */
function vaultStorage(ctx: BlockSqlContext): boolean {
  const storage = ctx.text("secretStorage", "vault");

  if (storage !== "vault" && storage !== "column") {
    throw new TypeError(
      `blocks.credentials.options.secretStorage must be "vault" or "column", not "${storage}"`,
    );
  }

  const vault = storage === "vault";

  if (!ctx.has("secrets", vault ? "vaultId" : "secret")) {
    throw new TypeError(
      `blocks.credentials: secretStorage "${storage}" needs the secrets table's ${vault ? "vaultId" : "secret"} column`,
    );
  }

  return vault;
}

/**
 * The declarations and statements that turn a call's provider and name into an
 * adopted row's key: `tenant/<tenant>/` and `@<user id>` move into the tenant
 * and scope columns when the table has them, and a `vault` call names another
 * provider's row as `<provider>:<name>`.
 */
function adoptedKey(
  ctx: BlockSqlContext,
  fn: string,
): {
  readonly declare: string;
  readonly parse: string;
  readonly match: string;
} {
  const c = (logical: string): string => ctx.col("secrets", logical);
  const tenant = ctx.has("secrets", "tenant");
  const scope = ctx.has("secrets", "scope");

  const parse = [
    tenant
      ? `
  if v_name ~ '^tenant/[^/]+/.' then
    v_tenant := split_part(v_name, '/', 2);
    v_name := substr(v_name, length(v_tenant) + 9);
  end if;`
      : "",
    scope
      ? `
  if v_name ~ '@[^@/]+$' then
    v_scope := substring(v_name from '@([^@/]+)$');
    v_name := left(v_name, length(v_name) - length(v_scope) - 1);
  end if;`
      : "",
    `
  if v_provider = 'vault' and position(':' in v_name) > 1 then
    v_provider := split_part(v_name, ':', 1);
    v_name := substr(v_name, length(v_provider) + 2);
  end if;`,
  ].join("");

  const match = [
    `s.${c("provider")}::text = v_provider`,
    `s.${c("name")}::text = v_name`,
    ...(tenant ? [`s.${c("tenant")}::text is not distinct from v_tenant`] : []),
    ...(scope ? [`s.${c("scope")}::text is not distinct from v_scope`] : []),
  ].join(" and ");

  return {
    declare: `
  v_provider text := ${fn}.provider;
  v_name text := ${fn}.name;
  v_tenant text;
  v_scope text;`,
    parse,
    match,
  };
}

/**
 * Deleting a row, or replacing its `vaultId`, deletes the Vault secret it
 * pointed to.
 */
function vaultCleanup(ctx: BlockSqlContext, vault: boolean): string {
  const t = ctx.table("secrets");
  const trigger = ctx.trigger("credential_vault");

  if (!vault) {
    return `drop trigger if exists ${trigger} on ${t};`;
  }

  const id = ctx.col("secrets", "vaultId");

  return `
create or replace function ${ctx.fn("drop_credential_vault_secret")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' or old.${id} is distinct from new.${id} then
    delete from vault.secrets vs where vs.id = old.${id};
  end if;
  return null;
end;
$$;
revoke execute on function ${ctx.fn("drop_credential_vault_secret")}() from public, anon, authenticated;
drop trigger if exists ${trigger} on ${t};
create trigger ${trigger} after delete or update of ${id} on ${t}
  for each row execute function ${ctx.fn("drop_credential_vault_secret")}();`;
}

/** The three functions over an app's own secrets table. */
function adopted(ctx: BlockSqlContext): string {
  const fn = (name: string): string => ctx.fn(name);
  const vault = vaultStorage(ctx);
  const t = ctx.table("secrets");
  const c = (logical: string): string => ctx.col("secrets", logical);

  const raw = (logical: string): string =>
    sqlString(c(logical).replaceAll('"', ""));

  const get = adoptedKey(ctx, "credential_get");
  const set = adoptedKey(ctx, "credential_set");
  const del = adoptedKey(ctx, "credential_delete");

  const keys = ["provider", "name", "tenant", "scope"].filter((logical) =>
    ctx.has("secrets", logical),
  );

  const variable: Readonly<Record<string, string>> = {
    provider: "v_provider",
    name: "v_name",
    tenant: "v_tenant",
    scope: "v_scope",
  };

  const stored = vault ? "v_vault" : "credential_set.secret";
  const value = vault ? c("vaultId") : c("secret");

  const touch = ctx.has("secrets", "updatedAt")
    ? `, ${c("updatedAt")} = now()`
    : "";

  const insertColumns = [
    ...keys.map(c),
    value,
    ...(ctx.has("secrets", "updatedAt") ? [c("updatedAt")] : []),
  ];

  const insertValues = [
    ...keys.map((logical) => `v_row.${c(logical)}`),
    stored,
    ...(ctx.has("secrets", "updatedAt") ? ["now()"] : []),
  ];

  const store = vault
    ? `
  if v_vault is null then
    v_vault := vault.create_secret(
      credential_set.secret,
      'bs:cred:' || v_provider || ':' || v_name || ':' || gen_random_uuid()::text,
      coalesce(credential_set.description, 'better-supabase credential')
    );
  else
    perform vault.update_secret(v_vault, credential_set.secret);
  end if;`
    : "";

  return `${schemaPreamble(ctx)}
-- Third-party credentials live in the app's ${t}, ${
    vault ? "each row naming its Vault secret" : "each row holding its secret"
  }. Only the service role reads or writes them.
create or replace function ${fn("credential_get")}(provider text, name text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare${get.declare}
begin${guard("credential_get")}${get.parse}
  return (
    select ${vault ? "ds.decrypted_secret" : `s.${c("secret")}`} from ${t} s${
      vault
        ? `
    join vault.decrypted_secrets ds on ds.id = s.${c("vaultId")}`
        : ""
    }
    where ${get.match}
    limit 1
  );
end;
$$;
${serviceGrant(`${fn("credential_get")}(text, text)`)}

-- Stores or replaces a credential; returns its row's Vault id, or null when
-- the table keeps the secret in a column.
create or replace function ${fn("credential_set")}(provider text, name text, secret text, description text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare${set.declare}
  v_found boolean;
  v_vault uuid;
  v_row ${t};
begin${guard("credential_set")}
  if credential_set.secret is null or length(credential_set.secret) = 0 then
    raise exception 'a credential needs a value'
      using errcode = 'P0001', hint = 'CREDENTIAL_EMPTY';
  end if;${set.parse}
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'bs:cred:' || v_provider || ':' || v_name || ':' || coalesce(v_tenant, '') || ':' || coalesce(v_scope, ''), 0));
  select true${vault ? `, s.${c("vaultId")}` : ""} into v_found${vault ? ", v_vault" : ""} from ${t} s where ${set.match} limit 1;${store}
  if v_found then
    update ${t} s set ${value} = ${stored}${touch} where ${set.match};
  else
    v_row := jsonb_populate_record(null::${t}, jsonb_build_object(
      ${keys.map((logical) => `${raw(logical)}, ${variable[logical] ?? "null"}`).join(",\n      ")}
    ));
    insert into ${t} (${insertColumns.join(", ")})
    values (${insertValues.join(", ")});
  end if;
  ${credentialEvent(ctx, "credential.set", "credential_set")}
  return v_vault;
end;
$$;
${serviceGrant(`${fn("credential_set")}(text, text, text, text)`)}

-- Deletes a credential; false when there was none.
create or replace function ${fn("credential_delete")}(provider text, name text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare${del.declare}
begin${guard("credential_delete")}${del.parse}
  delete from ${t} s where ${del.match};
  if not found then
    return false;
  end if;
  ${credentialEvent(ctx, "credential.deleted", "credential_delete")}
  return true;
end;
$$;
${serviceGrant(`${fn("credential_delete")}(text, text)`)}
${vaultCleanup(ctx, vault)}`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  if (!ctx.manages) {
    return adopted(ctx);
  }

  const renamed = Object.keys(ctx.config.columns["secrets"] ?? {});

  if (renamed.length > 0) {
    throw new TypeError(
      `blocks.credentials.columns.secrets: the managed module keeps credentials in Vault by name, so ${renamed.join(", ")} maps to nothing; adopt your own table with ownership "adopt"`,
    );
  }

  const fn = (name: string): string => ctx.fn(name);

  return `${schemaPreamble(ctx)}
-- Third-party credentials live in Vault as bs:cred:<provider>:<name>; tables
-- keep a credential_ref that names them, never the secret. Only the service
-- role reads or writes them.
create or replace function ${fn("credential_get")}(provider text, name text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
begin${guard("credential_get")}
  return (
    select ds.decrypted_secret from vault.decrypted_secrets ds
    where ds.name = ${secretName("credential_get")}
  );
end;
$$;
${serviceGrant(`${fn("credential_get")}(text, text)`)}

-- Stores or replaces a credential; returns its Vault id.
create or replace function ${fn("credential_set")}(provider text, name text, secret text, description text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin${guard("credential_set")}
  if credential_set.secret is null or length(credential_set.secret) = 0 then
    raise exception 'a credential needs a value'
      using errcode = 'P0001', hint = 'CREDENTIAL_EMPTY';
  end if;
  select s.id into v_id from vault.secrets s where s.name = ${secretName("credential_set")};
  if v_id is null then
    v_id := vault.create_secret(
      credential_set.secret,
      ${secretName("credential_set")},
      coalesce(credential_set.description, 'better-supabase credential')
    );
  else
    perform vault.update_secret(v_id, credential_set.secret);
  end if;
  ${credentialEvent(ctx, "credential.set", "credential_set")}
  return v_id;
end;
$$;
${serviceGrant(`${fn("credential_set")}(text, text, text, text)`)}

-- Deletes a credential; false when there was none.
create or replace function ${fn("credential_delete")}(provider text, name text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin${guard("credential_delete")}
  delete from vault.secrets s where s.name = ${secretName("credential_delete")};
  if not found then
    return false;
  end if;
  ${credentialEvent(ctx, "credential.deleted", "credential_delete")}
  return true;
end;
$$;
${serviceGrant(`${fn("credential_delete")}(text, text)`)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "credential_get", args: ["text", "text"], returns: "text" },
    {
      name: "credential_set",
      args: ["text", "text", "text", "text"],
      returns: "uuid",
    },
    { name: "credential_delete", args: ["text", "text"], returns: "boolean" },
  ];
}

export const CREDENTIALS: BlockSqlDefinition = {
  name: "credentials",
  title: "Credentials in Vault",
  description:
    "Third-party tokens and API keys in Supabase Vault as bs:cred:<provider>:<name>, behind security definer credential_get, credential_set and credential_delete functions only the service role may call. vaultCredentials() in better-supabase/credentials resolves credential references through them.",
  requires: [],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 1,
  names: NAMES,
  adoptOptional: (ctx) => ({
    secrets: [
      ctx.text("secretStorage", "vault") === "column" ? "vaultId" : "secret",
    ],
  }),
  contract,
  build,
};
