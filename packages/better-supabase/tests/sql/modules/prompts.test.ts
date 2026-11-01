import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { moduleBody } from "../../../src/sql/render.ts";

const body = (modules: AnyBlocksConfig = {}) =>
  moduleBody("prompts", { modules })!;

describe("prompts module", () => {
  it("owns the version and label tables, service role only", () => {
    const sql = body();
    expect(sql).toContain(
      'create table if not exists "better_supabase"."prompt_versions" (',
    );
    expect(sql).toContain(
      'create table if not exists "better_supabase"."prompt_labels" (',
    );
    expect(sql).not.toMatch(/to authenticated/);

    for (const name of [
      "create_prompt_version",
      "get_prompt",
      "set_prompt_label",
      "list_prompt_versions",
    ]) {
      expect(sql).toMatch(
        new RegExp(
          `revoke execute on function "better_supabase"."${name}"\\([^)]*\\) from public, anon, authenticated`,
        ),
      );
    }
  });

  it("numbers versions under a lock per tenant and name", () => {
    expect(body()).toContain("pg_advisory_xact_lock");
  });

  it("caps the template size", () => {
    expect(body({ prompts: { options: { maxBytes: 2048 } } })).toContain(
      "between 1 and 2048",
    );
    expect(() => body({ prompts: { options: { maxBytes: 0 } } })).toThrow(
      /maxBytes/,
    );
  });
});
