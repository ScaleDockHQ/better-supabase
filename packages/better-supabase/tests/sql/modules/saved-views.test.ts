import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { ownTablesOf } from "../../fixtures/own-tables.ts";

const sqlOf = (
  modules: readonly string[] = ["saved-views"],
  layout: Parameters<typeof renderBlocks>[1] = {},
): string =>
  renderBlocks(modules, layout)
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
      `"team_id" in (select t::text from "better_supabase"."team_ids_of"((select auth.uid())) t)`,
    );
    expect(sql).toContain(
      `save_view.team in (select t::text from "better_supabase"."team_ids_of"((select auth.uid())) t)`,
    );
  });

  it("guards definer writes against read-only actors", () => {
    const sql = sqlOf();
    expect(sql).toMatch(/save_view[\s\S]*actor_may_write/);
  });

  it("keeps per-user preferences that only their user reads", () => {
    const sql = sqlOf();
    expect(sql).toContain(
      `"view_id" uuid not null references "better_supabase"."saved_views" ("id") on delete cascade`,
    );
    expect(sql).toContain(`primary key ("view_id", "user_id")`);
    expect(sql).toContain(`using ("user_id" = (select auth.uid()));`);
    expect(sql).toContain(
      `left join "better_supabase"."saved_view_preferences" p on p."view_id" = v."id" and p."user_id" = (select auth.uid())`,
    );
    expect(sql).toMatch(
      /set_view_preference"\(view_id uuid, make_default boolean, hide boolean, pin boolean\)[\s\S]*views\.read[\s\S]*SAVED_VIEW_NOT_FOUND/,
    );
  });

  it("clears the caller's other preferred default of the same list", () => {
    expect(sqlOf()).toContain(
      `and o."tenant_id" = v_row."tenant_id" and o."list" = v_row."list";`,
    );
  });

  it("duplicates a visible view through save_view", () => {
    const sql = sqlOf();
    expect(sql).toMatch(
      /duplicate_view"\(view_id uuid, scope text, name text, team text\)[\s\S]*SAVED_VIEW_NOT_FOUND[\s\S]*return "better_supabase"\."save_view"\(v_row\."tenant_id", v_row\."list",/,
    );
  });

  it("leaves preferences out when the app maps no table", () => {
    const modules: AnyBlocksConfig = {
      "saved-views": { tables: { preferences: null } },
    };

    const sql = sqlOf(["saved-views"], {
      modules,
      ownTables: ownTablesOf(modules),
    });

    expect(sql).not.toContain("saved_view_preferences");
    expect(sql).not.toContain("set_view_preference");
    expect(sql).toContain("duplicate_view");
  });

  it("renders nothing in custom mode", () => {
    expect(
      sqlOf(["saved-views"], {
        modules: { "saved-views": { mode: "custom" } },
      }),
    ).not.toContain("save_view");
  });
});

describe("saved-views module with the provider's teamIdsOf", () => {
  const provider = {
    modules: { permissions: { model: "provider" } },
    accessProvider: {
      name: "stub",
      scope: "organization",
      idType: "uuid",
      functions: {
        idsWith: "authz.ids_with({permission}, {scope})",
        isPlatform: "authz.is_platform({permission})",
        teamIdsOf: "authz.team_ids_of({user})",
      },
    },
  } as Parameters<typeof renderBlocks>[1];

  it("shares team views through the template without the teams module", () => {
    const sql = sqlOf(["saved-views"], provider);
    expect(sql).toContain(
      `"team_id" in (select t.id::text from authz.team_ids_of((select auth.uid())) as t(id))`,
    );
    expect(sql).not.toContain("and false");
  });

  it("makes team_ids_of() return the template's set", () => {
    const teams = renderBlocks(["teams"], provider)
      .filter((file) => file.module === "teams")
      .map((file) => file.contents)
      .join("\n");

    expect(teams).toContain(
      "from authz.team_ids_of(team_ids_of.member) as t(id)",
    );
  });

  it("keeps the teams block's own lookup under the roles model", () => {
    const sql = sqlOf(["teams", "saved-views"], { ...provider, modules: {} });

    expect(sql).not.toContain("authz.team_ids_of");
  });
});
