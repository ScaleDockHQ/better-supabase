import { describe, expect, it } from "vitest";

import { readFileFacts } from "../../../src/cli/schema-reader/index.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { moduleLayout } from "../../../src/sql/layout.ts";
import { ORDER } from "../../../src/sql/registry.ts";
import { renderBlocks } from "../../../src/sql/render.ts";

const CONFIG = {
  auth: { entitlements: { customer: "organizations.stripe_customer_id" } },
};

describe("rendered modules", () => {
  it.each(ORDER)("parse as Postgres SQL: %s", async (name) => {
    const files = renderBlocks(
      [name],
      moduleLayout(resolveConfig(CONFIG, "/project")),
    );

    expect(files.length).toBeGreaterThan(0);

    for (const file of files) {
      await expect(
        readFileFacts(file.contents, { path: file.path }),
      ).resolves.toBeDefined();
    }
  });
});
