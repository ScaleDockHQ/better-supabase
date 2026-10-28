import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { NEGATIVE } from "../../../src/list/filter-query.ts";
import { moduleBody, renderBlocks } from "../../../src/sql/render.ts";

const body = (modules: AnyBlocksConfig = {}) =>
  moduleBody("automations", { modules })!;

const fn = (name: string) => `"better_supabase"."${name}"`;

describe("automations block", () => {
  it("keeps rules, their versions, evaluations and the field catalog", () => {
    const sql = body();

    for (const table of [
      "rules",
      "rule_versions",
      "rule_evaluations",
      "rule_fields",
    ]) {
      expect(sql).toContain(
        `create table if not exists "better_supabase"."${table}"`,
      );
    }

    expect(sql).toContain('"rank" text collate "C"');
  });

  it("grants the pure evaluator to everyone and the sync and run to the service role", () => {
    const sql = body();

    expect(sql).toContain(
      `grant execute on function ${fn("rule_evaluate")}(jsonb, jsonb, jsonb, text, timestamptz) to anon, authenticated, service_role;`,
    );
    expect(sql).toContain(
      `grant execute on function ${fn("sync_rule_fields")}(text, jsonb) to service_role;`,
    );
    expect(sql).toMatch(
      /grant execute on function "better_supabase"\."run_rules"\([^)]*\) to service_role;/,
    );
  });

  it("renders every negative operator from the shared table", () => {
    const sql = body();

    for (const [negative, base] of Object.entries(NEGATIVE)) {
      expect(sql).toContain(`when '${negative}' then '${base}'`);
    }
  });

  it("checks the rules permissions", () => {
    const sql = body();

    for (const permission of [
      "automations.read",
      "automations.write",
      "automations.publish",
      "automations.manage",
    ]) {
      expect(sql).toContain(`'${permission}'`);
    }
  });

  it("takes its limits from the block options", () => {
    const sql = body({
      automations: {
        options: { maxConditions: 7, maxDepth: 2, maxActions: 3 },
      },
    });

    expect(sql).toContain("if v_count > 7 then");
    expect(sql).toContain("if depth > 2 then");
    expect(sql).toContain("jsonb_array_length(v_actions) > 3 then");
  });

  describe("the enable and disable options", () => {
    const quotes = (options: Readonly<Record<string, unknown>> = {}): string =>
      renderBlocks(["automations", "orders", "quotes"], {
        modules: { automations: { options } },
      })
        .filter((file) => file.module === "quotes")
        .map((file) => file.contents)
        .join("\n");

    const ships = (sql: string): string | undefined =>
      /'quotes\.quote_to_order'.*::jsonb, (true|false)\)/.exec(sql)?.[1];

    it("keeps the block's own choice by default", () => {
      expect(ships(quotes())).toBe("false");
    });

    it("turns a default on with enable, and disable wins over it", () => {
      expect(ships(quotes({ enable: ["quotes.quote_to_order"] }))).toBe("true");
      expect(
        ships(
          quotes({
            enable: ["quotes.quote_to_order"],
            disable: ["quotes.quote_to_order"],
          }),
        ),
      ).toBe("false");
    });

    it("refuses a key that names no default automation", () => {
      expect(() => quotes({ disable: ["quote to order"] })).toThrow(
        /no default automation key/,
      );
    });
  });
});
