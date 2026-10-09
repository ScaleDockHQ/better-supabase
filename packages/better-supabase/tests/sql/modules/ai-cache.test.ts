import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import { moduleBody } from "../../../src/sql/registry.ts";

const body = (modules: ModulesConfig = {}) =>
  moduleBody("ai-cache", { modules })!;

describe("ai-cache module", () => {
  it("owns the entries table, service role only", () => {
    const sql = body();
    expect(sql).toContain(
      'create table if not exists "better_supabase"."ai_cache_entries" (',
    );
    expect(sql).not.toMatch(/to authenticated/);
    for (const name of [
      "ai_cache_get",
      "ai_cache_set",
      "ai_cache_delete",
      "purge_ai_cache",
    ]) {
      expect(sql).toMatch(
        new RegExp(
          `revoke execute on function "better_supabase"."${name}"\\([^)]*\\) from public, anon, authenticated`,
        ),
      );
    }
  });

  it("caps the TTL and the entry size", () => {
    const sql = body({
      "ai-cache": { options: { maxTtl: 3600, maxBytes: 2048 } },
    });
    expect(sql).toContain("least(ai_cache_set.ttl, 3600)");
    expect(sql).toContain("<= 2048");
  });

  it("rejects options that are not whole numbers", () => {
    expect(() => body({ "ai-cache": { options: { maxTtl: 1.5 } } })).toThrow(
      /maxTtl/,
    );
    expect(() => body({ "ai-cache": { options: { maxBytes: 0 } } })).toThrow(
      /maxBytes/,
    );
  });
});
