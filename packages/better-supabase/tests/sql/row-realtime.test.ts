import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../src/sql/index.ts";

const dataOf = (names: string[]) =>
  renderBlocks(names, {})
    .filter((file) => file.kind === "data" && file.module === "tasks")
    .map((file) => file.contents)
    .join("\n");

const schemaOf = (names: string[], module = "tasks", layout = {}) =>
  renderBlocks(names, layout)
    .filter((file) => file.kind === "schema" && file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("subject.realtime on block entities", () => {
  it("declares the entity table's triggers in the schema file when realtime-tables is installed", () => {
    const sql = schemaOf(["realtime-tables", "tasks"]);

    expect(sql).toContain(
      `create trigger bsb_realtime_insert after insert on "better_supabase"."tasks" referencing new table as new_rows for each statement execute function better_supabase.broadcast_changes('tenant_id', 'tenant');`,
    );
    expect(sql).toContain(
      `create trigger bsb_realtime_update after update on "better_supabase"."tasks" referencing old table as old_rows new table as new_rows`,
    );
    expect(sql).toContain(
      `create trigger bsb_realtime_delete after delete on "better_supabase"."tasks" referencing old table as old_rows`,
    );
    expect(dataOf(["realtime-tables", "tasks"])).not.toContain(
      "track_realtime",
    );
  });

  it("declares the app tables of config.realtime as static triggers", () => {
    const sql = schemaOf(["realtime-tables"], "realtime-tables", {
      realtimeTables: ["customers", "public.notes", "audit_log"],
      realtimeGlobal: ["audit_log"],
      realtimeUsers: { notes: "author_id" },
      tenantColumn: "organization_id",
    });

    expect(sql).toContain(
      "create trigger bsb_realtime_insert after insert on public.customers referencing new table as new_rows for each statement execute function better_supabase.broadcast_changes('organization_id', 'tenant');",
    );
    expect(sql).toContain(
      "execute function better_supabase.broadcast_changes('author_id', 'user');",
    );
    expect(sql).toContain(
      "create trigger bsb_realtime after insert or update or delete on public.audit_log for each statement execute function better_supabase.broadcast_changes();",
    );
    expect(sql).not.toContain("track_realtime('public.notes'");
  });

  it("leaves the table alone without realtime-tables", () => {
    expect(dataOf(["tasks"])).not.toContain("track_realtime");
  });
});
