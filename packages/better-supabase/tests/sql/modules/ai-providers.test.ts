import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import { moduleBody } from "../../../src/sql/registry.ts";

const body = (modules: ModulesConfig = {}) =>
  moduleBody("ai-providers", { modules })!;

describe("ai-providers module", () => {
  it("owns keys, batches, batch items and sandboxes", () => {
    const sql = body();
    for (const table of [
      "ai_provider_keys",
      "ai_batches",
      "ai_batch_items",
      "ai_sandboxes",
    ]) {
      expect(sql).toContain(
        `create table if not exists "better_supabase"."${table}" (`,
      );
    }
  });

  it("stores keys as credential refs", () => {
    const sql = body();
    expect(sql).toMatch(/credential_ref" jsonb not null check/);
    expect(sql).not.toMatch(/"(api_?key|token|secret)"/);
  });

  it("keeps resolving, polling and the idle stop to the service role", () => {
    const sql = body();
    for (const name of [
      "ai_provider_keys_for",
      "delete_ai_provider_keys",
      "due_ai_batches",
      "update_ai_batch",
      "save_ai_batch_items",
      "register_ai_sandbox",
      "idle_ai_sandboxes",
      "finish_ai_sandbox_stop",
    ]) {
      expect(sql).toMatch(
        new RegExp(
          `revoke execute on function "better_supabase"."${name}"\\([^)]*\\) from public, anon, authenticated`,
        ),
      );
    }
  });

  it("takes the poll and idle intervals from its options", () => {
    const sql = body({
      "ai-providers": { options: { pollEvery: 120, idleAfter: 900 } },
    });
    expect(sql).toContain("interval '120 seconds'");
    expect(sql).toContain("default 900");
    expect(() =>
      body({ "ai-providers": { options: { pollEvery: -1 } } }),
    ).toThrow(/pollEvery/);
  });
});
