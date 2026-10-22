import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (
  layout: Parameters<typeof renderBlocks>[1] = {},
  modules: readonly string[] = ["relations"],
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "relations")
    .map((file) => file.contents)
    .join("\n");

const withOptions = (options: Record<string, unknown>) => ({
  modules: { relations: { options } },
});

describe("relations module", () => {
  it("creates the table with a unique edge and no self links", () => {
    const sql = sqlOf();
    expect(sql).toContain(
      `unique ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id")`,
    );
    expect(sql).toContain(
      `check (not ("source_type" = "target_type" and "source_id" = "target_id"))`,
    );
    expect(sql).toContain("relations_target_idx");
  });

  it("lists every kind and inverse name with its flags", () => {
    const sql = sqlOf();
    expect(sql).toContain(
      `('blocks', 'blocks', false, true, false, false, 'blocked_by')`,
    );
    expect(sql).toContain(
      `('blocked_by', 'blocks', true, true, false, false, 'blocks')`,
    );
    expect(sql).toContain(
      `('parent', 'parent', false, true, true, false, 'children')`,
    );
    expect(sql).toContain(
      `('relates', 'relates', false, false, false, true, 'relates')`,
    );
  });

  it("takes the kinds from options", () => {
    const sql = sqlOf(
      withOptions({
        kinds: { reports_to: { cardinality: "one", acyclic: true } },
      }),
    );

    expect(sql).toContain(
      `('reports_to', 'reports_to', false, true, true, false, 'reports_to')`,
    );
    expect(sql).not.toContain("'blocked_by'");
  });

  it("rejects kinds that clash or contradict", () => {
    expect(() =>
      sqlOf(withOptions({ kinds: { blocks: { inverse: "blocks" } } })),
    ).toThrow(/named twice/);
    expect(() => sqlOf(withOptions({ kinds: { "Bad-Name": {} } }))).toThrow(
      /lowercase/,
    );
    expect(() =>
      sqlOf(
        withOptions({ kinds: { relates: { symmetric: true, inverse: "x" } } }),
      ),
    ).toThrow(/symmetric kind/);
    expect(() =>
      sqlOf(withOptions({ kinds: { x: { cardinality: "two" } } })),
    ).toThrow(/one or many/);
    expect(() => sqlOf(withOptions({ kinds: { x: { size: 1 } } }))).toThrow(
      /not an option/,
    );
    expect(() => sqlOf(withOptions({ kinds: [] }))).toThrow(
      /must be an object/,
    );
  });

  it("checks both ends against the subjects and locks acyclic kinds", () => {
    const sql = sqlOf(
      withOptions({
        subjects: {
          task: {
            table: "public.tasks",
            permission: "tasks.read",
            idType: "uuid",
          },
        },
      }),
    );

    expect(sql).toContain(
      `when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (link.target_id)::uuid`,
    );
    expect(sql).toContain(
      "pg_advisory_xact_lock(hashtext(link.tenant::text || ':relation:' || v_kind))",
    );
    expect(sql).toContain(
      `when 'task' then v_table := '"public"."tasks"'; v_id_col := 'id'; v_tenant_col := 'organization_id';`,
    );
  });

  it("guards the definer writes and renders nothing in custom mode", () => {
    expect(sqlOf()).toContain("actor_may_write");
    expect(sqlOf({ modules: { relations: { mode: "custom" } } })).toBe("");
  });
});
