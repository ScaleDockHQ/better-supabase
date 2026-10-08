import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { schemaPreamble, SERVICE_CALLER } from "../shared.ts";

const NAMES: ModuleNames = { tables: {} };

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const fn = (name: string): string => ctx.fn(name);
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
  const grant = (signature: string): string =>
    `revoke execute on function ${signature} from public, anon, authenticated;
grant execute on function ${signature} to service_role;`;

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
${grant(`${fn("credential_get")}(text, text)`)}

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
  return v_id;
end;
$$;
${grant(`${fn("credential_set")}(text, text, text, text)`)}

-- Deletes a credential; false when there was none.
create or replace function ${fn("credential_delete")}(provider text, name text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin${guard("credential_delete")}
  delete from vault.secrets s where s.name = ${secretName("credential_delete")};
  return found;
end;
$$;
${grant(`${fn("credential_delete")}(text, text)`)}`;
}

function contract(): readonly ModuleContractFunction[] {
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

export const CREDENTIALS: ModuleDefinition = {
  name: "credentials",
  title: "Credentials in Vault",
  description:
    "Third-party tokens and API keys in Supabase Vault as bs:cred:<provider>:<name>, behind security definer credential_get, credential_set and credential_delete functions only the service role may call. vaultCredentials() in better-supabase/credentials resolves credential references through them.",
  requires: [],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
