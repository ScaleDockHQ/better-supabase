import { describe, expect, it } from "vitest";

import type { ModuleConfig } from "../../src/config/modules.ts";

import { apiWrappers } from "../../src/sql/api-schema.ts";
import { renderModules, SQL_MODULES } from "../../src/sql/registry.ts";

const schemaFile = (name: string, api: NonNullable<ModuleConfig["api"]>) =>
  renderModules([name], { modules: { [name]: { api } } }).find(
    (file) => file.module === name && file.kind === "schema",
  )!.contents;

describe("sql.modules.<module>.api", () => {
  it("wraps every function a module grants to anon, authenticated or service_role", () => {
    for (const module of Object.values(SQL_MODULES)) {
      if (module.target !== "schema") continue;
      try {
        renderModules([module.name]);
      } catch {
        continue;
      }
      const file = schemaFile(module.name, "api");
      const granted = [
        ...file.matchAll(
          /^grant execute on function "?better_supabase"?\.[^\n(]+\([^\n]*\bto [^;]*\b(?:anon|authenticated|service_role)\b/gm,
        ),
      ].length;
      const wrapped = [...file.matchAll(/create or replace function "api"\./g)]
        .length;
      expect({ module: module.name, wrapped }).toEqual({
        module: module.name,
        wrapped: granted,
      });
    }
  });

  it("wraps the service functions of jobs, idempotency and the webhook inbox", () => {
    for (const [name, fn] of [
      ["jobs", "enqueue_job"],
      ["idempotency", "begin_idempotent"],
      ["webhook-inbox", "receive_webhook"],
    ] as const) {
      expect(schemaFile(name, "api")).toContain(
        `create or replace function "api"."${fn}"(`,
      );
    }
    for (const module of Object.values(SQL_MODULES)) {
      if (module.target !== "schema") continue;
      try {
        expect({
          module: module.name,
          loops: /foreach fn in array array\[[\s\S]*?grant execute/.test(
            renderModules([module.name]).find(
              (file) => file.module === module.name,
            )?.contents ?? "",
          ),
        }).toEqual({ module: module.name, loops: false });
      } catch (cause) {
        if (cause instanceof TypeError) continue;
        throw cause;
      }
    }
  });

  it("writes security invoker wrappers with the same arguments and grants", () => {
    const file = schemaFile("settings", {
      schema: "api",
      functions: ["set_user_setting", "get_user_settings"],
    });
    expect(file).toContain(`create schema if not exists "api";`);
    expect(file)
      .toContain(`create or replace function "api"."set_user_setting"(key text, value jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_user_setting"($1, $2) $$;
revoke execute on function "api"."set_user_setting"(text, jsonb) from public;
grant execute on function "api"."set_user_setting"(text, jsonb) to authenticated, service_role;`);
    expect(file).toContain(`"api"."get_user_settings"()`);
    expect(file).not.toContain(`"api"."reset_user_setting"`);
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
