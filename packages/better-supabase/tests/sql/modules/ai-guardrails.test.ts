import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { moduleBody } from "../../../src/sql/render.ts";

const body = (modules: AnyBlocksConfig = {}) =>
  moduleBody("ai-guardrails", { modules })!;

describe("ai-guardrails module", () => {
  it("owns the policy and decision tables, service role only", () => {
    const sql = body();
    expect(sql).toContain(
      'create table if not exists "better_supabase"."guardrail_policies" (',
    );
    expect(sql).toContain(
      'create table if not exists "better_supabase"."guardrail_decisions" (',
    );
    expect(sql).not.toMatch(/to authenticated/);

    for (const name of [
      "set_guardrail_policy",
      "get_guardrail_policy",
      "record_guardrail_decision",
      "list_guardrail_decisions",
      "purge_guardrail_decisions",
    ]) {
      expect(sql).toMatch(
        new RegExp(
          `revoke execute on function "better_supabase"."${name}"\\([^)]*\\) from public, anon, authenticated`,
        ),
      );
    }
  });

  it("keeps a hash of the content, never the content", () => {
    const sql = body();
    expect(sql).toContain("content_hash");
    expect(sql).not.toMatch(/\bcontent text\b/);
  });

  it("validates the retention interval", () => {
    expect(
      body({ "ai-guardrails": { options: { retention: "30 days" } } }),
    ).toContain("interval '30 days'");
    expect(() =>
      body({ "ai-guardrails": { options: { retention: "forever" } } }),
    ).toThrow(/retention/);
  });
});
