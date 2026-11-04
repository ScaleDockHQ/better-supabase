import { describe, expect, it } from "vitest";

import { applyCodemod, CODEMODS } from "../../src/cli/codemod.ts";

const codemod = CODEMODS["0.53"]!;

describe("codemod 0.53", () => {
  it("moves blockConfig to blocks.config", () => {
    const result = applyCodemod(
      codemod,
      'import { blockConfig } from "@/lib/supabase/blocks.generated";',
    );

    expect(result.text).toBe(
      'import { blockConfig } from "@/lib/supabase/blocks.config";',
    );
  });

  it("splits a mixed import and keeps the extension", () => {
    const result = applyCodemod(
      codemod,
      'import { blockConfig, permissions } from "./blocks.generated.ts";',
    );

    expect(result.text).toBe(
      [
        'import { blockConfig } from "./blocks.config.ts";',
        'import { permissions } from "./blocks.generated.ts";',
      ].join("\n"),
    );
  });

  it("leaves other imports alone", () => {
    const source = 'import { permissions } from "./blocks.generated";';

    expect(applyCodemod(codemod, source).text).toBe(source);
  });
});
