import { describe, expect, it } from "vitest";

import { emitBlockConfig } from "../../../src/cli/gen/blocks.ts";
import { emitHooks, hookNames } from "../../../src/cli/gen/hooks.ts";
import { resolveConfig } from "../../../src/config/resolve.ts";

describe("hooks.ts", () => {
  it("names a list hook and a record hook per db property", () => {
    expect(hookNames("customers")).toEqual({
      list: "useCustomers",
      one: "useCustomer",
    });
    expect(hookNames("leadScoring")).toEqual({
      list: "useLeadScoringList",
      one: "useLeadScoring",
    });
  });

  it("writes React hooks by default and nothing with hooks: false", () => {
    const config = resolveConfig(
      { adapters: ["next"], blocks: { comments: {} } },
      "/project",
    );

    const file = emitHooks(config, ["customers"]);

    expect(file?.path).toBe("src/lib/supabase/hooks.ts");
    expect(file?.contents).toContain('"use client";');
    expect(file?.contents).toContain(
      'import { defineDataHooks } from "better-supabase/react";',
    );
    expect(file?.contents).toContain(
      'export const { useList: useCustomers, useOne: useCustomer } = defineDataHooks(\n  "customers",\n  (db: AppDb) => db.customers,\n);',
    );
    expect(file?.contents).not.toContain('"comments"');

    expect(
      emitHooks({ ...config, hooks: false }, ["customers"]),
    ).toBeUndefined();
  });

  it("imports the framework the config names", () => {
    const config = resolveConfig({ gen: { hooks: "vue" } }, "/project");

    expect(emitHooks(config, ["customers"])?.contents).toContain(
      'from "better-supabase/vue";',
    );
  });
});

describe("blocks.generated.ts instance map", () => {
  it("exports every instance under its db property", () => {
    const config = resolveConfig(
      { blocks: { comments: {}, "support-notes": { block: "comments" } } },
      "/project",
    );

    const contents = emitBlockConfig(config, {})?.contents ?? "";

    expect(contents).toContain("export const blocks = {");
    expect(contents).toMatch(/^ {2}comments: \w+,$/m);
    expect(contents).toMatch(/^ {2}"support-notes": \w+,$/m);
  });
});
