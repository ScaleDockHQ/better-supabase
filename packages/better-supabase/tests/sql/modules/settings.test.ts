import { toStandardJsonSchema } from "@valibot/to-json-schema";
import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { defineSettings } from "../../../src/blocks/settings/index.ts";
import { renderModules } from "../../../src/sql/registry.ts";

const sqlOf = (
  names: readonly string[],
  options?: Readonly<Record<string, unknown>>,
): string =>
  renderModules(names, {
    modules: options ? { settings: { options } } : {},
  })
    .filter((file) => file.contents.includes("user_settings"))
    .map((file) => file.contents)
    .join("\n");

describe("settings module", () => {
  it("writes both tables with their policies and functions", () => {
    const sql = sqlOf(["settings"]);
    expect(sql).toMatch(/create table if not exists \S+user_settings/);
    expect(sql).toMatch(/create table if not exists \S+organization_settings/);
    expect(sql).toContain("'settings.read'");
    expect(sql).toContain("'settings.update'");
    expect(sql).toContain("set_organization_setting");
    expect(sql).not.toContain("jsonb_matches_schema");
  });

  it("writes a check per key with a JSON Schema", () => {
    const settings = defineSettings({
      user: {
        theme: { schema: toStandardJsonSchema(v.picklist(["light", "dark"])) },
      },
      organization: {
        plan: { schema: { type: "string" } as never },
        // A plain Valibot schema has no Standard JSON Schema.
        note: { schema: v.string() },
      },
    });
    const sql = sqlOf(["jsonb-schemas", "settings"], { schemas: settings });
    expect(sql).toContain('add constraint "bs_json_value_theme"');
    expect(sql).toContain(
      `check ("key" <> 'theme' or extensions.jsonb_matches_schema(`,
    );
    expect(sql).toContain("bs_json_value_plan");
    expect(sql).not.toContain("bs_json_value_note");
  });

  it("accepts plain { user, organization } maps", () => {
    const sql = sqlOf(["jsonb-schemas", "settings"], {
      schemas: { user: { theme: { type: "string" } } },
    });
    expect(sql).toContain("bs_json_value_theme");
  });

  it("needs jsonb-schemas for checks and rejects other shapes", () => {
    expect(() =>
      sqlOf(["settings"], { schemas: { user: { theme: { type: "string" } } } }),
    ).toThrow(/add the jsonb-schemas module/);
    expect(() => sqlOf(["settings"], { schemas: "x" })).toThrow(
      /pass \{ user, organization, platform \}/,
    );
    expect(() => sqlOf(["settings"], { schemas: { user: [] } })).toThrow(
      /object of key to schema/,
    );
  });

  it("guards platform keys with their own permission and read rule", () => {
    const sql = sqlOf(["jsonb-schemas", "settings"], {
      platform: { permission: "platform.settings", read: "staff" },
      schemas: {
        platform: {
          fee: {
            schema: { type: "number" },
            permission: "billing.platform",
            read: "public",
          },
          banner: { schema: { type: "string" }, read: "authenticated" },
        },
      },
    });
    expect(sql).toMatch(/create table if not exists \S+platform_settings/);
    expect(sql).toContain(
      "better_supabase.is_platform(case \"key\" when 'fee' then 'billing.platform' when 'banner' then 'platform.settings' else 'platform.settings' end)",
    );
    expect(sql).toContain(
      "case \"key\" when 'fee' then true when 'banner' then true else coalesce(better_supabase.is_platform('platform.settings'), false) end",
    );
    expect(sql).toContain(`for select to anon\n  using ("key" in ('fee'))`);
    expect(sqlOf(["settings"])).toContain(
      "better_supabase.is_platform('settings.manage')",
    );
    expect(sqlOf(["settings"], { platform: { read: "public" } })).toContain(
      "for select to anon\n  using (true)",
    );
    expect(() =>
      sqlOf(["settings"], { platform: { read: "everyone" } }),
    ).toThrow(/read must be public, authenticated, staff/);
    expect(() => sqlOf(["settings"], { platform: "x" })).toThrow(
      /must be \{ permission\?, read\? \}/,
    );
    expect(() =>
      sqlOf(["settings"], {
        schemas: { platform: { fee: { permission: 1 } } },
      }),
    ).toThrow(/permission must be a permission key/);
  });
});
