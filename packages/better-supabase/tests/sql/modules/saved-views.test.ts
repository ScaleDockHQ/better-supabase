import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/render.ts";

const sqlOf = (
  modules: readonly string[] = ["saved-views"],
  layout: Parameters<typeof renderModules>[1] = {},
): string =>
  renderModules(modules, layout)
    .filter((file) => file.module === "saved-views")
    .map((file) => file.contents)
    .join("\n");

describe("saved-views module", () => {
  it("creates the table with scope, kind and state checks", () => {
    const sql = sqlOf();
    expect(sql).toContain(
      `"scope" text not null default 'user' check ("scope" in ('user', 'team', 'tenant'))`,
    );
    expect(sql).toContain(
      `check ("kind" in ('table', 'board', 'calendar', 'timeline', 'gantt'))`,
    );
    expect(sql).toContain(`pg_column_size("state") <= 65536`);
    expect(sql).toContain(`"rank" text collate "C" not null default 'V'`);
    expect(sql).toContain("saved_views_default_idx");
  });

  it("needs views.share for a team or tenant view", () => {
    const sql = sqlOf();
    expect(sql).toContain(
      `if save_view.scope <> 'user' and not (v_service or coalesce(better_supabase.can('tenant', save_view.tenant, 'views.share'), false)) then`,
    );
  });

  it("hides team views without the teams module", () => {
    const sql = sqlOf();
    expect(sql).toContain(`("scope" = 'team' and false)`);
    expect(sql).not.toContain("team_ids_of");
  });

  it("shows team views to the team's members with the teams module", () => {
    const sql = sqlOf(["saved-views", "teams"]);
    expect(sql).toContain(
      `"team_id" in (select t::text from "better_supabase"."team_ids_of"(auth.uid()) t)`,
    );
    expect(sql).toContain(
      `save_view.team in (select t::text from "better_supabase"."team_ids_of"(auth.uid()) t)`,
    );
  });

  it("guards definer writes against read-only actors", () => {
    const sql = sqlOf();
    expect(sql).toMatch(/save_view[\s\S]*actor_may_write/);
  });

  it("renders nothing in custom mode", () => {
    expect(
      sqlOf(["saved-views"], {
        modules: { "saved-views": { mode: "custom" } },
      }),
    ).not.toContain("save_view");
  });
});
