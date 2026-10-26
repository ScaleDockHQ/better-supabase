import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { detectExisting } from "../../src/cli/init-existing.ts";
import { resolveConfig } from "../../src/config/index.ts";

const root = join(
  import.meta.dirname,
  "../../../../apps/examples/existing-app",
);

describe("the existing-app example", () => {
  it("is a plain Supabase app that init detects", async () => {
    const found = await detectExisting(resolveConfig({}, root), {}, root);

    expect(found?.schemaFiles).toBe(1);
    expect(found?.migrations).toBe(0);
  });
});
