import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { SCORES } from "../../../src/sql/modules/scores.ts";
import { renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const sqlOf = (modules: readonly string[], layout: Layout = {}): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "scores")
    .map((file) => file.contents)
    .join("\n");

describe("scores module", () => {
  it("validates model trees with the rules block and keeps one current score", () => {
    const sql = sqlOf(["scores"]);

    expect(sql).toContain('"better_supabase"."rule_check"(');
    expect(sql).toContain('"better_supabase"."rule_matches"(');
    expect(sql).toContain('"scores_current_idx"');
    expect(sql).toContain("jsonb_array_length(v_rules) > 100");
    expect(sql).toContain("jsonb_array_length(v_metrics) > 50");
  });

  it("reads vote scores only with the reactions block", () => {
    const alone = sqlOf(["scores"]);
    expect(alone).toContain("not in ('field')");
    expect(alone).not.toContain("reaction_scores");

    const voted = sqlOf(["reactions", "scores"]);
    expect(voted).toContain("not in ('field', 'votes')");
    expect(voted).toContain('"better_supabase"."reaction_scores"');
  });

  it("takes rule and metric limits from the options", () => {
    const sql = sqlOf(["scores"], {
      modules: { scores: { options: { maxRules: 5, maxMetrics: 3 } } },
    });

    expect(sql).toContain("jsonb_array_length(v_rules) > 5");
    expect(sql).toContain("jsonb_array_length(v_metrics) > 3");
    expect(() =>
      sqlOf(["scores"], { modules: { scores: { options: { maxRules: 0 } } } }),
    ).toThrow("blocks.scores.options.maxRules must be a whole number");
  });

  it("renders nothing for custom mode", () => {
    expect(sqlOf(["scores"], { modules: { scores: { mode: "custom" } } })).toBe(
      "",
    );
    // SAFETY: custom mode returns before reading anything else on the context.
    const custom = { mode: "custom" } as unknown as BlockSqlContext;

    expect(SCORES.build(custom, {})).toBe("");
  });
});
