import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import type { BlockConfig } from "../../src/config/blocks.ts";

import { BLOCK_MANIFESTS } from "../../src/blocks/registry.ts";
import { apiWrappers } from "../../src/sql/api-schema.ts";
import { clientFunctions } from "../../src/sql/client-functions.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";
import { renderBlocks } from "../../src/sql/render.ts";

const schemaFile = (name: string, api: NonNullable<BlockConfig["api"]>) =>
  renderBlocks([name], { modules: { [name]: { api } } }).find(
    (file) => file.module === name && file.kind === "schema",
  )!.contents;

// list_roles and set_permission_override exist only under the catalog model,
// and the approval policy functions only with tenant policies.
const MODULE_OPTIONS: Readonly<Record<string, Record<string, unknown>>> = {
  permissions: { model: "catalog" },
  approvals: { options: { tenantPolicies: true } },
};

// Record access requests exist only next to a subject with a team.
const MODULE_BLOCKS: Readonly<Record<string, readonly string[]>> = {
  "access-requests": ["subjects"],
};

const TEAM_SUBJECT = {
  record: { table: "public.records", team: { actions: ["read"] } },
};

/** The schema file, with `billing` for a module that needs its customer column. */
const schemaFileWith = (
  name: string,
  api: NonNullable<BlockConfig["api"]>,
): string => {
  try {
    return renderBlocks([...(MODULE_BLOCKS[name] ?? []), name], {
      modules: { [name]: { ...MODULE_OPTIONS[name], api } },
      ...(MODULE_BLOCKS[name] ? { subjects: TEAM_SUBJECT } : {}),
    }).find((file) => file.module === name && file.kind === "schema")!.contents;
  } catch {
    return renderBlocks(["billing", name], {
      modules: { [name]: { api } },
    }).find((file) => file.module === name && file.kind === "schema")!.contents;
  }
};

const SRC_DIR = join(import.meta.dirname, "../../src");
const BLOCKS_DIR = join(SRC_DIR, "blocks");

const withoutComments = (source: string): string =>
  source.replaceAll(/\/\*[\s\S]*?\*\//g, "").replaceAll(/^\s*\/\/.*$/gm, "");

const literals = (sources: readonly string[]): Set<string> =>
  new Set(
    sources.flatMap((source) =>
      [...withoutComments(source).matchAll(/"([a-z_][a-z0-9_]*)"/g)].map(
        (match) => match[1]!,
      ),
    ),
  );

const read = (dir: string, files: readonly string[]): string[] =>
  files.map((file) => readFileSync(join(dir, file), "utf-8"));

/**
 * The wrapped functions whose names the TypeScript side spells out: each
 * block's own files for its modules, and the transport code outside the blocks
 * (credentials, streams, the Chat SDK state) for every module.
 */
function clientCalls(): Record<string, string[]> {
  const shared = literals(
    read(
      SRC_DIR,
      readdirSync(SRC_DIR, { recursive: true, encoding: "utf-8" }).filter(
        (file) =>
          file.endsWith(".ts") &&
          !["blocks", "cli", "sql"].some((dir) => file.startsWith(`${dir}/`)),
      ),
    ).filter((source) =>
      /\bBlock(?:Transport|Call)\b|\bblockCall\(/.test(source),
    ),
  );

  const own = new Map<string, Set<string>>();

  for (const dir of readdirSync(BLOCKS_DIR)) {
    const path = join(BLOCKS_DIR, dir);

    if (!existsSync(join(path, "manifest.ts"))) {
      continue;
    }

    const names = literals(
      read(
        path,
        readdirSync(path).filter((file) => file.endsWith(".ts")),
      ),
    );

    for (const block of BLOCK_MANIFESTS) {
      if (
        readFileSync(join(path, "manifest.ts"), "utf-8").includes(
          `name: "${block.name}"`,
        )
      ) {
        for (const module of block.sql) {
          own.set(module, names);
        }
      }
    }
  }

  const calls: Record<string, string[]> = {};

  for (const module of Object.values(SQL_MODULES)) {
    if (module.target !== "schema") {
      continue;
    }

    const file = schemaFileWith(module.name, "api");
    const names = own.get(module.name) ?? new Set<string>();

    const called = [
      ...new Set(
        [
          ...file.matchAll(
            /create or replace function "api"\."([a-z_0-9]+)"\(/g,
          ),
        ].map((match) => match[1]!),
      ),
    ]
      .filter((name) => names.has(name) || shared.has(name))
      .toSorted();

    if (called.length > 0) {
      calls[module.name] = called;
    }
  }

  return Object.fromEntries(
    Object.entries(calls).toSorted(([a], [b]) => a.localeCompare(b)),
  );
}

describe("blocks.<module>.api", () => {
  it("wraps every function a module grants to anon, authenticated or service_role", () => {
    for (const module of Object.values(SQL_MODULES)) {
      if (module.target !== "schema") {
        continue;
      }

      try {
        renderBlocks([module.name]);
      } catch {
        continue;
      }

      const file = schemaFile(module.name, "api");
      const internal = new Set(module.internal);

      const granted = [
        ...file.matchAll(
          /^grant execute on function "?better_supabase"?\.([^\n(]+)\([^\n]*\bto [^;]*\b(?:anon|authenticated|service_role)\b/gm,
        ),
      ].filter((match) => !internal.has(match[1]!.replaceAll('"', ""))).length;

      const wrapped = [...file.matchAll(/create or replace function "api"\./g)]
        .length;

      expect({ module: module.name, wrapped }).toEqual({
        module: module.name,
        wrapped: granted,
      });
    }
  });

  it("drops the wrappers of signatures the module itself drops", () => {
    const notifications = schemaFile("notifications", "api");
    const drop = `drop function if exists "api"."mark_notifications_read"(uuid[], uuid);`;
    expect(notifications).toContain(drop);
    expect(notifications.indexOf(drop)).toBeLessThan(
      notifications.indexOf(
        `create or replace function "api"."mark_notifications_read"`,
      ),
    );
    expect(notifications).toContain(
      `drop function if exists "api"."notification_page"(uuid, text, text[], text[], text, integer, integer);`,
    );

    const dropping = `create or replace function better_supabase.counts(tenant uuid)
returns integer
language sql
as $$ select 1 $$;
drop function if exists better_supabase.mark_read(uuid[]);
create or replace function better_supabase.mark_read(ids uuid[], tenant uuid)
returns integer
language sql
as $$ select 1 $$;
grant execute on function better_supabase.counts(uuid) to authenticated;
grant execute on function better_supabase.mark_read(uuid[], uuid) to authenticated;`;

    expect(
      apiWrappers(
        dropping,
        "better_supabase",
        { schema: "api", functions: ["counts"] },
        "x",
      ),
    ).not.toContain(`drop function if exists "api".`);
    expect(
      apiWrappers(
        dropping,
        "better_supabase",
        { schema: "api", functions: ["counts"] },
        "x",
        [],
        ["mark_read"],
      ),
    ).toContain(`drop function if exists "api"."mark_read"(uuid[]);`);
  });

  it("writes no entry point for the helpers policies and triggers call", () => {
    const organizations = schemaFile("organizations", "api");
    expect(organizations).not.toContain(
      `create or replace function "api"."guard_membership_role"`,
    );
    expect(organizations).toContain(
      `drop function if exists "api"."guard_membership_role"(uuid, uuid, text, uuid, text);`,
    );
    expect(organizations).toContain(
      `create or replace function "api"."update_member_role"`,
    );
    const invitations = schemaFile("invitations", "api");
    expect(invitations).not.toContain(
      `create or replace function "api"."invitation_tenant_ids"`,
    );
    expect(invitations).toContain(
      `create or replace function "api"."my_invitations"`,
    );

    for (const [name, helper] of [
      ["comments", "comment_subject_readable"],
      ["attachments", "attachment_object_allowed"],
      ["webhooks-in", "incoming_webhook_tenant_ids"],
      ["data-lifecycle", "data_export_object_allowed"],
      ["mfa", "mfa_satisfied"],
      ["sessions", "session_active"],
    ] as const) {
      expect(schemaFile(name, "api")).not.toContain(
        `create or replace function "api"."${helper}"`,
      );
    }

    expect(() =>
      schemaFile("organizations", {
        schema: "api",
        functions: ["guard_membership_role"],
      }),
    ).toThrow(/guard_membership_role is a helper/);

    const sql = `create or replace function better_supabase.only_helper()
returns boolean
language sql
as $$ select true $$;
grant execute on function better_supabase.only_helper() to authenticated;`;

    expect(
      apiWrappers(sql, "better_supabase", { schema: "api" }, "x", [
        "only_helper",
      ]),
    ).toContain(`drop function if exists "api"."only_helper"();`);
    expect(
      apiWrappers(sql, "better_supabase", { schema: "api" }, "x", ["other"]),
    ).toContain(`create or replace function "api"."only_helper"()`);
  });

  it("wraps the service functions of jobs, idempotency and the webhook inbox", () => {
    for (const [name, fn] of [
      ["queue", "enqueue_job"],
      ["idempotency", "begin_idempotent"],
      ["webhook-inbox", "receive_webhook"],
    ] as const) {
      expect(schemaFile(name, "api")).toContain(
        `create or replace function "api"."${fn}"(`,
      );
    }

    for (const module of Object.values(SQL_MODULES)) {
      if (module.target !== "schema") {
        continue;
      }

      try {
        expect({
          module: module.name,
          loops: /foreach fn in array array\[[\s\S]*?grant execute/.test(
            renderBlocks([module.name]).find(
              (file) => file.module === module.name,
            )?.contents ?? "",
          ),
        }).toEqual({ module: module.name, loops: false });
      } catch (cause) {
        if (cause instanceof TypeError) {
          continue;
        }

        throw cause;
      }
    }
  });

  it("writes security invoker wrappers with the same arguments and grants", () => {
    const file = schemaFile("settings", {
      schema: "api",
      functions: ["set_user_setting"],
    });

    expect(file).toContain(`create schema if not exists "api";`);
    expect(file)
      .toContain(`create or replace function "api"."set_user_setting"(key text, value jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_user_setting"($1, $2) $$;
revoke execute on function "api"."set_user_setting"(text, jsonb) from public, anon;
grant execute on function "api"."set_user_setting"(text, jsonb) to authenticated, service_role;`);
    expect(file).toContain(`"api"."get_user_settings"()`);

    const sql = `create or replace function better_supabase.listed()
returns integer
language sql
as $$ select 1 $$;
create or replace function better_supabase.left_out()
returns integer
language sql
as $$ select 1 $$;
grant execute on function better_supabase.listed() to authenticated;
grant execute on function better_supabase.left_out() to authenticated;`;

    const narrowed = apiWrappers(
      sql,
      "better_supabase",
      { schema: "api", functions: ["listed"] },
      "x",
    );

    expect(narrowed).toContain(`"api"."listed"()`);
    expect(narrowed).not.toContain(`"api"."left_out"()`);
  });

  it("wraps every function the client calls when functions lists fewer", () => {
    const file = schemaFile("rate-limit", {
      schema: "api",
      functions: ["check_rate_limit"],
    });

    for (const [name, types] of [
      ["check_rate_limit", "text, text, integer, interval"],
      ["check_rate_limits", "jsonb"],
      ["purge_rate_limits", "integer"],
    ] as const) {
      expect(file).toContain(`create or replace function "api"."${name}"(`);
      expect(file).toContain(
        `revoke execute on function "api"."${name}"(${types}) from public, anon, authenticated;
grant execute on function "api"."${name}"(${types}) to service_role;`,
      );
    }

    expect(file).toMatch(
      /create or replace function "api"\."check_rate_limits"\(hits jsonb\)\nreturns jsonb\nlanguage sql\nsecurity invoker\n/,
    );
    expect(file).not.toContain(`"api"."set_rate_limit"`);

    const missing = Object.keys(SQL_MODULES).flatMap((module) => {
      const names = clientFunctions(module);

      if (names.length === 0) {
        return [];
      }

      const narrowed = schemaFileWith(module, { schema: "api", functions: [] });

      return names
        .filter(
          (name) =>
            !narrowed.includes(`create or replace function "api"."${name}"(`),
        )
        .map((name) => `${module}: ${name}`);
    });

    expect(missing).toEqual([]);
  });

  it("lists every function a client calls over a transport", () => {
    const listed = Object.fromEntries(
      Object.keys(SQL_MODULES)
        .map((module) => [module, [...clientFunctions(module)]] as const)
        .filter(([, names]) => names.length > 0)
        .toSorted(([a], [b]) => a.localeCompare(b)),
    );

    expect(clientCalls()).toEqual(listed);
  });

  it("revokes execute from anon on every function it does not grant to anon", () => {
    const signature = (text: string) =>
      text.replaceAll('"', "").replaceAll(/\s+/g, " ").trim();

    const missing: string[] = [];

    for (const module of Object.values(SQL_MODULES)) {
      if (module.target !== "schema") {
        continue;
      }

      let file: string;

      try {
        file = schemaFile(module.name, "api");
      } catch {
        continue;
      }

      const revoked = new Set(
        [
          ...file.matchAll(
            /^revoke execute on function ([^\n]+?\)) from ([^;]+);/gm,
          ),
        ]
          .filter((match) =>
            match[2]!.split(",").some((role) => role.trim() === "anon"),
          )
          .map((match) => signature(match[1]!)),
      );

      for (const match of file.matchAll(
        /^grant execute on function ([^\n]+?\)) to ([^;]+);/gm,
      )) {
        const roles = match[2]!.split(",").map((role) => role.trim());

        if (roles.includes("anon")) {
          continue;
        }

        if (!revoked.has(signature(match[1]!))) {
          missing.push(`${module.name}: ${signature(match[1]!)}`);
        }
      }
    }

    expect(missing).toEqual([]);
  });

  it("selects from functions that return rows and keeps defaults", () => {
    const sql = `create or replace function better_supabase.list_things(tenant uuid, max_items integer default 50, variadic tags text[] default '{}')
returns setof public.things
language sql
as $$ select 1 $$;
grant execute on function better_supabase.list_things(uuid, integer, text[]) to anon;`;

    const out = apiWrappers(sql, "better_supabase", { schema: "api" }, "x");
    expect(out).toContain(
      `"api"."list_things"(tenant uuid, max_items integer default 50, variadic tags text[] default '{}')`,
    );
    expect(out).toContain(
      `select * from "better_supabase"."list_things"($1, $2, variadic $3)`,
    );
    expect(out).toContain("to anon;");
  });

  it("wraps service-role functions for servers that only reach PostgREST", () => {
    const file = schemaFile("flags", "api");
    expect(file).toContain(
      `create or replace function "api"."flag_definitions"()`,
    );
    expect(file).toContain(
      `grant execute on function "api"."flag_definitions"() to service_role;`,
    );

    const sql = `create or replace function better_supabase.claims(user_id uuid)
returns jsonb
language sql
as $$ select '{}'::jsonb $$;
grant execute on function better_supabase.claims(uuid) to service_role, supabase_auth_admin;`;

    expect(
      apiWrappers(sql, "better_supabase", { schema: "api" }, "x"),
    ).toContain(
      `grant execute on function "api"."claims"(uuid) to service_role;`,
    );
  });

  it("refuses an API schema that is the module schema or an unknown function", () => {
    expect(() =>
      apiWrappers("", "better_supabase", { schema: "better_supabase" }, "x"),
    ).toThrow(/must differ/);
    expect(() =>
      schemaFile("settings", { schema: "api", functions: ["missing"] }),
    ).toThrow(/missing is not a settings function/);
  });
});
