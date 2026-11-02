import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { moduleBody, renderBlocks } from "../../../src/sql/render.ts";

const body = (modules: AnyBlocksConfig = {}) =>
  moduleBody("ai-evals", { modules })!;

const FUNCTIONS: Record<string, string> = {
  create_eval_dataset: "text, uuid, text",
  add_eval_items: "uuid, jsonb",
  list_eval_items: "uuid, uuid, uuid, integer",
  create_eval_run: "uuid, text, integer, text, jsonb",
  record_eval_result: "uuid, uuid, text, jsonb, text, integer",
  finish_eval_run: "uuid, text",
  compare_eval_runs: "uuid, uuid, numeric",
};

describe("ai-evals module", () => {
  it("owns the dataset, item, run and result tables, service role only", () => {
    const sql = body();

    for (const table of [
      "eval_datasets",
      "eval_items",
      "eval_runs",
      "eval_results",
    ]) {
      expect(sql).toContain(
        `create table if not exists "better_supabase"."${table}" (`,
      );
    }

    expect(sql).not.toMatch(/to authenticated/);

    for (const name of Object.keys(FUNCTIONS)) {
      expect(sql).toMatch(
        new RegExp(
          `revoke execute on function "better_supabase"."${name}"\\([^)]*\\) from public, anon, authenticated`,
        ),
      );
    }
  });

  it("refuses feedback imports without the ai-chat block", () => {
    expect(body()).toContain("EVAL_FEEDBACK_UNAVAILABLE");
  });

  it("reads rated replies from ai-chat when it is installed", () => {
    const sql = renderBlocks(["ai-chat", "ai-evals"])
      .filter((file) => file.contents.includes("add_eval_items_from_feedback"))
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain('"ai_message_feedback"');
    expect(sql).not.toContain("EVAL_FEEDBACK_UNAVAILABLE");
  });

  it("caps the dataset size", () => {
    expect(body({ "ai-evals": { options: { maxItems: 50 } } })).toContain(
      "> 50 then",
    );
    expect(() => body({ "ai-evals": { options: { maxItems: 0 } } })).toThrow(
      /maxItems/,
    );
  });

  it("compares runs of one dataset only", () => {
    expect(body()).toContain("EVAL_RUN_MISMATCH");
  });
});
