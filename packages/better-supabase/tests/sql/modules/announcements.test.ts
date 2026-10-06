import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import { renderModules } from "../../../src/sql/registry.ts";

const sqlOf = (names: readonly string[], modules: ModulesConfig = {}): string =>
  renderModules(names, { modules })
    .filter((file) => file.contents.includes("announcement_dismissals"))
    .map((file) => file.contents)
    .join("\n");

describe("announcements module", () => {
  it("writes the tables, the functions and the broadcast", () => {
    const sql = sqlOf(["announcements"]);
    expect(sql).toMatch(/create table if not exists \S+announcements" \(/);
    expect(sql).toMatch(
      /create table if not exists \S+announcement_dismissals/,
    );
    expect(sql).toContain("'announcements.manage'");
    expect(sql).toContain("in ('all', 'tenant', 'role')");
    expect(sql).not.toContain("tenant_entitlements");
    expect(sql).toContain("'announcement_changed',\n      'announcements',");
    expect(sql).toContain("realtime.topic()) = 'announcements'");
  });

  it("adds the plan audience with entitlements", () => {
    const sql = sqlOf(["organizations", "entitlements", "announcements"]);
    expect(sql).toContain("in ('all', 'tenant', 'role', 'plan')");
    expect(sql).toContain("better_supabase.tenant_entitlements(v_tenant)");
  });

  it("takes the topic and event from the options", () => {
    const sql = sqlOf(["announcements"], {
      announcements: { options: { topic: "app:news", event: "news" } },
    });
    expect(sql).toContain("'news',\n      'app:news',");
    expect(() =>
      sqlOf(["announcements"], {
        announcements: { options: { topic: "no spaces" } },
      }),
    ).toThrow("sql.modules.announcements.options.topic");
  });
});
