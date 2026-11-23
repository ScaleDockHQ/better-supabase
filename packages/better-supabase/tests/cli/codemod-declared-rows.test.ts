import { describe, expect, it } from "vitest";

import type { BetterSupabaseConfig } from "../../src/config/index.ts";

import {
  declaredRowsCodemod,
  declaredRowsMove,
} from "../../src/cli/codemod-declared-rows.ts";
import { planRows } from "../../src/cli/rows/plan.ts";
import { resolveConfig } from "../../src/config/index.ts";

const CONFIG = `export default {
  blocks: {
    pipelines: {
      on: {
        deal: {
          categories: { open: "open", won: "success" },
          stages: [
            { key: "lead", name: "Lead", category: "open", probability: 10 },
            { key: "won", name: "Won", category: "won" },
          ],
        },
      },
    },
    approvals: {
      options: {
        policies: { invoice: { send: { steps: [{ approvers: { role: "admin" }, required: 1 }] } } },
      },
    },
  },
};
`;

const run = (text: string) =>
  declaredRowsCodemod().project!({
    config: resolveConfig(
      {
        subjects: { deal: { table: "public.deals" } },
        blocks: {
          pipelines: {
            on: {
              deal: {
                categories: { open: "open", won: "success" },
                stages: [
                  {
                    key: "lead",
                    name: "Lead",
                    category: "open",
                    probability: 10,
                  },
                  { key: "won", name: "Won", category: "won" },
                ],
              },
            },
          },
          approvals: {
            options: {
              policies: {
                invoice: {
                  send: {
                    steps: [{ approvers: { role: "admin" }, required: 1 }],
                  },
                },
              },
            },
          },
        },
      } as unknown as BetterSupabaseConfig,
      "/project",
    ),
    sql: [],
    configFile: "/project/better-supabase.config.ts",
    configText: text,
  });

describe("declaredRowsMove", () => {
  it("moves option set items and brand items", () => {
    const move = declaredRowsMove({
      "option-sets": {
        on: {
          project: {
            priority: {
              levels: { min: 0, max: 3 },
              items: [{ key: "low", label: "Low", level: 0 }],
              brands: { acme: [{ key: "mid", label: "Mid", level: 1 }] },
            },
          },
        },
      },
    });

    expect(
      move.files["option-sets"]?.map((row) => [row.subject, row.key]),
    ).toEqual([
      ["project.priority", "low"],
      ["project.priority@acme", "mid"],
    ]);
    expect(move.remove).toEqual([
      ["blocks", "option-sets", "on", "project", "priority", "items"],
      ["blocks", "option-sets", "on", "project", "priority", "brands"],
    ]);
  });
});

describe("declared-rows codemod", () => {
  it("does nothing when the config declares no items", async () => {
    const result = await declaredRowsCodemod().project!({
      config: resolveConfig({ blocks: { tags: {} } }, "/project"),
      sql: [],
    });

    expect(result).toEqual({ files: [], review: [] });
  });

  it("moves stages and floors into rows files and out of the config", async () => {
    const { files, review } = await run(CONFIG);
    const rows = Object.fromEntries(files.map((file) => [file.path, file]));

    expect(Object.keys(rows).toSorted()).toEqual([
      "/project/better-supabase.config.ts",
      "/project/supabase/rows/approvals.sql",
      "/project/supabase/rows/pipelines.sql",
    ]);
    expect(rows["/project/supabase/rows/pipelines.sql"]?.contents).toContain(
      "('pipeline_stage', 'deal', 'lead', 0,",
    );
    expect(rows["/project/supabase/rows/approvals.sql"]?.contents).toContain(
      "('approval_floor', 'invoice:send', 'invoice:send', 0,",
    );

    const config = rows["/project/better-supabase.config.ts"]?.contents ?? "";

    expect(config).not.toContain("stages");
    expect(config).not.toContain("policies");
    expect(config).toContain("categories");
    expect(review.some((line) => line.message.includes("db rows"))).toBe(true);
  });

  it("writes files that db rows accepts", async () => {
    const { files } = await run(CONFIG);

    const rows = new Map(
      files
        .filter((file) => file.path.includes("/rows/"))
        .map((file) => [
          file.path.replaceAll(/^.*\/|\.sql$/g, ""),
          file.contents,
        ]),
    );

    const plan = await planRows(
      rows,
      new Map(),
      new Date("2026-11-22T10:00:00Z"),
    );

    expect(plan.migrations).toHaveLength(2);
  });
});
