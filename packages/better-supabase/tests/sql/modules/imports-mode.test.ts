import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { moduleBody, renderBlocks } from "../../../src/sql/render.ts";

// Import mode (ADR 0141): the session function, the option policy and every
// hook the mode guards.

const imports = (options: Readonly<Record<string, unknown>> = {}) =>
  renderBlocks(["audit", "imports"], { modules: { imports: { options } } })
    .filter((file) => file.module === "imports")
    .map((file) => file.contents)
    .join("\n");

const golden = (name: string): string =>
  readFileSync(new URL(`../__golden__/${name}.sql`, import.meta.url), "utf-8");

const body = (module: string, modules: AnyBlocksConfig = {}) =>
  moduleBody(module, { modules })!;

describe("import mode session", () => {
  const sql = imports();

  it("begins a session for the service role on a running run", () => {
    expect(sql).toContain(
      'create or replace function "better_supabase"."begin_import_session"(run uuid)',
    );
    expect(sql).toContain("only the service role can begin an import session");
    expect(sql).toContain("perform set_config('better_supabase.import_run'");
    expect(sql).toContain(
      "perform set_config('better_supabase.correlation_id', 'import:'",
    );
    expect(sql).toContain(
      'grant execute on function "better_supabase"."begin_import_session"(uuid) to service_role;',
    );
  });

  it("opens the session in import_upsert_batch and restores the settings", () => {
    const upsert = sql.slice(
      sql.indexOf('"import_upsert_batch"(run uuid'),
      sql.indexOf('"import_resolve"(run uuid'),
    );

    expect(upsert).toContain('"begin_import_session"(v_run_id)');
    expect(upsert).toContain(
      "perform set_config(v_name, v_previous ->> v_name",
    );
  });

  it("only reports the run to the service role", () => {
    const fn = body("audit").slice(
      body("audit").indexOf("function better_supabase.import_run()"),
    );

    expect(fn).toContain("session_user::text");
    expect(fn).toContain("'service_role'");
  });
});

describe("imports.events", () => {
  it("skips an event unless the option lists its type", () => {
    expect(imports()).toContain(
      "set_config('better_supabase.import_events', '{}', true)",
    );
    expect(
      imports({ events: { "order.created": "tag", default: "emit" } }),
    ).toContain('{"order.created":"tag","default":"emit"}');
  });

  it("refuses a mode that is not skip, tag or emit", () => {
    expect(() => imports({ events: { "order.created": "fire" } })).toThrow(
      /must be skip, tag or emit/,
    );
    expect(() => imports({ events: ["order.created"] })).toThrow(
      /must map event types/,
    );
  });

  it("applies the policy in emit_event", () => {
    const sql = body("outbox");

    expect(sql).toContain("v_run uuid := better_supabase.import_run();");
    expect(sql).toContain("if v_mode = 'skip' then");
    expect(sql).toContain("jsonb_build_object('importRunId', v_run)");
  });
});

describe("imports.audit", () => {
  it("defaults to rows and writes no summary entry", () => {
    const sql = imports();

    expect(sql).toContain(
      "set_config('better_supabase.import_audit', 'rows', true)",
    );
    expect(sql).not.toContain("'imported ' || v_entity");
  });

  it("summarizes per entity, only for an entity that wrote rows", () => {
    const sql = imports({ audit: "summary" });

    expect(sql).toContain(
      "set_config('better_supabase.import_audit', 'summary', true)",
    );
    expect(sql).toContain("'imported ' || v_entity");
    expect(sql).toContain("actor_kind => 'integration'");
    expect(sql).toContain("correlation_id => 'import:' || v_run_id::text");
    expect(sql).toContain("'inserted')::integer, 0) + coalesce");
  });

  it("refuses another value", () => {
    expect(() => imports({ audit: "none" })).toThrow(/rows or summary/);
  });

  it("tags entries as integration and skips row entries in summary mode", () => {
    const sql = body("audit");

    expect(sql).toContain(
      "when better_supabase.import_run() is not null then 'integration'",
    );
    expect(sql).toContain(
      "current_setting('better_supabase.import_audit', true) = 'summary'",
    );
  });
});

describe("guarded hooks", () => {
  it("skips state machine events and writes one imported history row", () => {
    const sql = body("state-machine", {
      "state-machine": {
        options: {
          machines: {
            order: {
              table: "public.orders",
              column: "status",
              initial: "new",
              transitions: { new: ["done"], done: [] },
            },
          },
        },
      },
    });

    expect(sql).toContain(
      "if better_supabase.import_run() is not null and new",
    );
    expect(sql).toContain("'imported'");
    expect(sql).toContain("null::text");
  });

  it("guards notify, accounting auto-posting and document-driven stock", () => {
    const guard = "better_supabase.import_run() is not null";

    expect(golden("comments")).toContain(
      "if better_supabase.import_run() is null then",
    );

    for (const name of ["orders", "shipments", "invoices"]) {
      expect(golden(name)).toContain(`if not ${guard} then`);
    }
  });
});
