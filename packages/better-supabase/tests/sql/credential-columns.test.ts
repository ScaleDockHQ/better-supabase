import { describe, expect, it } from "vitest";

import { moduleBody, SQL_MODULES } from "../../src/sql/registry.ts";

/** Modules that own secrets by design: Vault itself and webhook signing. */
const ALLOWED = (name: string): boolean =>
  name === "credentials" || name === "vault" || name.startsWith("webhook");

/** Not credentials: the domain challenge is published in a DNS TXT record. */
const KNOWN = new Set([
  '"better_supabase"."organization_domains".verification_token',
]);

/** Columns named like a token that hold no third-party credential, per module. */
const NOT_CREDENTIALS: Readonly<Record<string, readonly string[]>> = {
  // Hook tokens address a Workflow SDK hook; the DDL is @workflow/world-postgres's.
  "workflow-sdk-world": [
    "workflow.workflow_hooks.token",
    "workflow.workflow_hooks.token_retention_until",
    "?.token",
    "?.token_retention_until",
  ],
  // A lock token proves who holds a Chat SDK thread lock when it is released.
  "chat-sdk-state": ['"better_supabase"."chat_state_locks".token'],
};

const SENSITIVE = /token|secret|api_?key/;
const CREATE_TABLE =
  /create table(?: if not exists)?\s+([\w."]+)\s*\(([\s\S]*?)\n\);/gi;
const ADD_COLUMN = /add column(?: if not exists)?\s+"?(\w+)"?/gi;

/** `table.column` for every column a module's SQL creates or adds. */
function columnsOf(sql: string): string[] {
  const columns: string[] = [];
  for (const [, table, body] of sql.matchAll(CREATE_TABLE))
    for (const line of body!.split("\n")) {
      const name = /^\s*"?([a-z_][a-z0-9_]*)"?\s+[a-z]/i.exec(line)?.[1];
      if (
        name !== undefined &&
        !/^(constraint|primary|unique|check|foreign|exclude|like)$/i.test(name)
      )
        columns.push(`${table}.${name}`);
    }
  for (const [, name] of sql.matchAll(ADD_COLUMN)) columns.push(`?.${name}`);
  return columns;
}

/** Columns named like a token or key that hold more than a hash. */
function credentialColumns(sql: string): string[] {
  return columnsOf(sql).filter((column) => {
    const name = column.slice(column.lastIndexOf(".") + 1);
    return (
      SENSITIVE.test(name) && !name.endsWith("_hash") && !KNOWN.has(column)
    );
  });
}

describe("credential columns", () => {
  it("parses created and added columns", () => {
    expect(
      credentialColumns(`create table public.grants (
  id uuid primary key,
  access_token text,
  token_hash text not null,
  credential_ref jsonb,
  constraint grants_token check (true)
);
alter table public.grants add column if not exists api_key text;`),
    ).toEqual(["public.grants.access_token", "?.api_key"]);
  });

  it.each(
    Object.keys(SQL_MODULES).filter(
      (name) => name !== "pgtap" && !ALLOWED(name),
    ),
  )("%s stores credentials as a credential_ref", (name) => {
    const sql = moduleBody(name) ?? "";
    const allowed = NOT_CREDENTIALS[name] ?? [];
    expect(
      credentialColumns(sql).filter((column) => !allowed.includes(column)),
    ).toEqual([]);
  });
});
