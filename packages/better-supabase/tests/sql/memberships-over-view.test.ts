import { describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { renderBlocks } from "../../src/sql/render.ts";

const VIEW = "public.organization_memberships";
const QUOTED = '"public"."organization_memberships"';

const OPTIONAL_NULLS: Record<string, string | null> = {
  updatedAt: null,
  lastUsedAt: null,
};

const layout = (
  columns: readonly string[] = [
    "organization_id",
    "user_id",
    "role",
    "created_at",
  ],
  memberships: Record<string, string | null> = OPTIONAL_NULLS,
): BlockSqlLayout => ({
  modules: {
    memberships: { tables: { memberships: VIEW }, columns: { memberships } },
    "share-links": {},
  },
  ownTables: { [VIEW]: "supabase/schemas/010_memberships.sql" },
  ownViews: { [VIEW]: { updatable: false } },
  ownColumns: { [VIEW]: columns },
});

const render = (source: BlockSqlLayout = layout()): string =>
  renderBlocks(["memberships", "share-links"], source)
    .map((file) => file.contents)
    .join("\n");

/** The statements that name the view, without the functions' bodies. */
const ddlOnView = (sql: string): string[] =>
  sql
    .split("\n")
    .filter(
      (line) =>
        /^(create|alter|grant|revoke|drop|comment)\b/i.test(line) &&
        line.includes("organization_memberships"),
    );

describe("memberships over a view", () => {
  it("writes the functions that read the view and no DDL on it", () => {
    const sql = render();

    expect(ddlOnView(sql)).toEqual([]);
    expect(sql).toContain(
      `-- ${VIEW} is the app's view: this block writes only the functions that read it.`,
    );
    expect(sql).not.toMatch(
      /enable row level security[^;]*organization_memberships/,
    );

    for (const fn of [
      "current_tenant_id",
      "member_organization_ids",
      "has_organization_role",
      "membership_claims",
      "organization_member_role",
    ]) {
      expect(sql).toMatch(new RegExp(`function [^(]*${fn}\\(`));
    }

    expect(sql).toContain(`from ${QUOTED} m`);
  });

  it("reads no column the view lacks", () => {
    const sql = render();

    const reads = sql
      .split("\n")
      .filter((line) => line.includes(QUOTED))
      .join("\n");

    expect(reads).not.toContain("disabled_at");
    expect(reads).not.toContain("updated_at");
    expect(reads).not.toContain("last_used_at");
  });

  it("treats optional columns the view lacks as null without a mapping", () => {
    expect(render(layout(undefined, {}))).toBe(render());
  });

  it("stops on a required column the view lacks", () => {
    expect(() =>
      render(layout(["organization_id", "user_id", "created_at"])),
    ).toThrow(
      `blocks.memberships reads ${VIEW}.role, which the view doesn't have.`,
    );
  });
});
