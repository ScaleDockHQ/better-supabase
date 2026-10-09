import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import {
  moduleBody,
  renderModules,
  upgradePlan,
} from "../../../src/sql/registry.ts";

const body = (modules: ModulesConfig = {}) =>
  moduleBody("ai-providers", { modules })!;

describe("ai-providers module", () => {
  it("owns keys, batches and batch items, and leaves sandboxes to ai-chat", () => {
    const sql = body();
    for (const table of ["ai_provider_keys", "ai_batches", "ai_batch_items"]) {
      expect(sql).toContain(
        `create table if not exists "better_supabase"."${table}" (`,
      );
    }
    expect(sql).not.toContain("ai_sandboxes");
  });

  it("stores keys as credential refs", () => {
    const sql = body();
    expect(sql).toMatch(/credential_ref" jsonb not null check/);
    expect(sql).not.toMatch(/"(api_?key|token|secret)"/);
  });

  it("keeps resolving and polling to the service role", () => {
    const sql = body();
    for (const name of [
      "ai_provider_keys_for",
      "delete_ai_provider_keys",
      "due_ai_batches",
      "update_ai_batch",
      "save_ai_batch_items",
    ]) {
      expect(sql).toMatch(
        new RegExp(
          `revoke execute on function "better_supabase"."${name}"\\([^)]*\\) from public, anon, authenticated`,
        ),
      );
    }
  });

  it("rejects a key credential_ref outside the key's tenant", () => {
    expect(body()).toContain(
      "(save_ai_provider_key.credential_ref ->> 'tenant') is distinct from (save_ai_provider_key.tenant)::text",
    );
  });

  it("takes the poll interval from its options", () => {
    const sql = body({ "ai-providers": { options: { pollEvery: 120 } } });
    expect(sql).toContain("interval '120 seconds'");
    expect(() =>
      body({ "ai-providers": { options: { pollEvery: -1 } } }),
    ).toThrow(/pollEvery/);
  });

  it("passes its idleAfter to ai-chat's sandboxes", () => {
    const chat = renderModules(["ai-chat", "ai-providers"], {
      modules: { "ai-providers": { options: { idleAfter: 900 } } },
    })
      .map((file) => file.contents)
      .find((contents) =>
        contents.includes(
          'create table if not exists "better_supabase"."ai_sandboxes"',
        ),
      );
    expect(chat).toContain("default 900");
  });

  it("stops the upgrade while sandboxes have no ai-chat to move to", () => {
    const [alone] = upgradePlan([{ module: "ai-providers", version: 1 }]);
    expect(alone!.steps[0]!.sql).toContain(
      "ai_sandboxes moved to the ai-chat module",
    );
    const withChat = upgradePlan([
      { module: "ai-chat", version: 2 },
      { module: "ai-providers", version: 1 },
    ]).find((plan) => plan.module === "ai-providers");
    expect(withChat!.steps[0]!.sql).toBe("");
  });
});
