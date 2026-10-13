import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";

const sqlOf = (layout: Parameters<typeof renderModules>[1] = {}): string =>
  renderModules(["custom-fields"], layout)
    .filter((file) => file.module === "custom-fields")
    .map((file) => file.contents)
    .join("\n");

describe("custom-fields module", () => {
  it("appends a rank key per tenant and entity on a new definition", () => {
    const sql = sqlOf();
    expect(sql).toContain(`"rank" text collate "C" not null default 'V',`);
    expect(sql).toContain(
      `where d."tenant_id" = save_field_definition.tenant and d."entity" = save_field_definition.entity;`,
    );
    expect(sql).toContain(`do update set "label" = excluded."label"`);
    expect(sql).not.toMatch(/do update set[^\n]*"rank"/);
    expect(sql).toContain(
      `"rank_field_definition"(definition uuid, rank text)`,
    );
    expect(sql).not.toContain("position");
  });

  it("has no rank in the inline layout", () => {
    const sql = sqlOf({
      modules: { "custom-fields": { options: { layout: "inline" } } },
    });
    expect(sql).not.toContain("rank_field_definition");
    expect(sql).not.toContain(`"rank"`);
  });

  it("backfills rank keys in position order when upgrading from version 1", () => {
    const [plan] = upgradePlan([{ module: "custom-fields", version: 1 }]);
    expect(plan).toMatchObject({ module: "custom-fields", from: 1, to: 2 });
    const sql = plan!.steps[0]!.sql;
    expect(sql).toContain(
      `row_number() over (partition by "tenant_id", "entity" order by position, "key", "id") as nth`,
    );
    expect(sql).toContain(
      `alter table "better_supabase"."field_definitions" drop column if exists position;`,
    );
  });

  it("skips the upgrade for the inline layout", () => {
    const [plan] = upgradePlan([{ module: "custom-fields", version: 1 }], {
      modules: { "custom-fields": { options: { layout: "inline" } } },
    });
    expect(plan!.steps[0]!.sql).toBe("");
  });
});
