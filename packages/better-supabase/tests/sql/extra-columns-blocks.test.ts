import { describe, expect, it } from "vitest";

import { renderModules } from "../../src/sql/render.ts";

/** Each module that takes `extraColumns`: the modules it needs, its table, and its write and read. */
const CASES = [
  {
    module: "push",
    needs: [],
    table: "push_devices",
    write: "register_push_device.fields",
    read: "push_tokens_for",
  },
  {
    module: "service-principals",
    needs: ["organizations"],
    table: "service_principals",
    write: "register_service_principal.fields",
    read: "service_principals_list",
  },
  {
    module: "relations",
    needs: ["organizations"],
    table: "relations",
    write: "link.fields",
    read: "relations_by_kind",
  },
  {
    module: "reminders",
    needs: ["organizations", "jobs"],
    table: "reminders",
    write: "save_reminder.fields",
    read: "save_reminder",
  },
  {
    module: "saved-views",
    needs: ["organizations"],
    table: "saved_views",
    write: "save_view.fields",
    read: "list_views",
  },
  {
    module: "promotions",
    needs: ["organizations", "catalog", "orders"],
    table: "promotions",
    write: "save_promotion.fields",
    read: "save_promotion",
  },
  {
    module: "pipelines",
    needs: ["organizations", "deals"],
    table: "pipelines",
    write: "save_pipeline.fields",
    read: "list_pipelines",
  },
  {
    module: "orders",
    needs: ["organizations", "catalog"],
    table: "orders",
    write: "place_order.fields",
    read: "order_json",
  },
  {
    module: "parties",
    needs: ["organizations"],
    table: "companies",
    write: "save_company.attrs",
    read: "list_companies",
  },
  {
    module: "quotes",
    needs: ["organizations"],
    table: "quotes",
    write: "(create_quote.attrs -> 'fields')",
    read: "create_quote",
  },
  {
    module: "notifications",
    needs: ["organizations"],
    table: "notification_events",
    write: "(notification -> 'fields')",
    read: "get_notification",
  },
  {
    module: "invitations",
    needs: ["organizations"],
    table: "invitations",
    write: "invite_member.fields",
    read: "my_invitations",
  },
] as const;

const sqlOf = (
  module: string,
  needs: readonly string[],
  options: Record<string, unknown> = {},
): string =>
  renderModules([...needs, module], { modules: { [module]: { options } } })
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("extraColumns on the notifications to settings blocks", () => {
  for (const entry of CASES) {
    it(`${entry.module}: adds the columns, writes them from fields and returns them`, () => {
      const plain = sqlOf(entry.module, entry.needs);
      const sql = sqlOf(entry.module, entry.needs, {
        extraColumns: { app_note: "text", app_rank: "integer default 0" },
      });
      expect(plain).not.toContain('"app_note"');
      expect(plain).not.toContain("'fields', jsonb_build_object(");
      expect(sql).toContain(
        `alter table "better_supabase"."${entry.table}" add column if not exists "app_note" text;`,
      );
      expect(sql).toContain(
        `add column if not exists "app_rank" integer default 0;`,
      );
      expect(sql).toContain(`${entry.write} ? 'app_note'`);
      expect(sql).toContain(
        `jsonb_populate_record(null::"better_supabase"."${entry.table}", `,
      );
      expect(sql).toMatch(
        /'fields', (\(select )?jsonb_build_object\('app_note', [a-z_]+\."app_note", 'app_rank', [a-z_]+\."app_rank"\)/,
      );
      const read = sql.indexOf(entry.read);
      expect(read).toBeGreaterThan(-1);
    });
  }

  it("rejects a column that shadows a key the reads return", () => {
    expect(() =>
      sqlOf("saved-views", ["organizations"], {
        extraColumns: { preferences: "jsonb" },
      }),
    ).toThrow(/shadows a column/);
    expect(() =>
      sqlOf("notifications", ["organizations"], {
        extraColumns: { read_at: "timestamptz" },
      }),
    ).toThrow(/shadows a column/);
  });

  it("only gives a function a fields parameter when the module has extra columns", () => {
    expect(sqlOf("push", [])).not.toContain("fields jsonb default null");
    expect(sqlOf("push", [], { extraColumns: { app_note: "text" } })).toContain(
      'register_push_device"(text, text, text, text, text, jsonb) to authenticated, service_role;',
    );
  });
});
