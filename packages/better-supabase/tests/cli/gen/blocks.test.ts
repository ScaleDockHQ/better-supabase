import { describe, expect, it } from "vitest";

import {
  blockConfigEntries,
  blockConfigPath,
  emitBlockConfig,
} from "../../../src/cli/gen/blocks.ts";
import { resolveConfig } from "../../../src/config/resolve.ts";

describe("blocks.generated.ts", () => {
  it("writes each installed block's schema, API schema and shared options", () => {
    const config = resolveConfig(
      {
        sql: { api: "api" },
        blocks: {
          tenant: {},
          access: {},
          attachments: { options: { requireScan: false, bucket: "files" } },
          notifications: { schema: "app_blocks" },
          comments: { api: false },
        },
      },
      "/project",
    );
    const entries = blockConfigEntries(config);
    expect(entries["attachments"]).toEqual({
      schema: "better_supabase",
      api: "api",
      options: { requireScan: false },
    });
    expect(entries["notifications"]).toEqual({
      schema: "app_blocks",
      api: "api",
      options: { topic: "notifications:{userId}" },
    });
    expect(entries["comments"]).toEqual({
      schema: "better_supabase",
      options: {},
    });
    // Blocks with only SQL get an entry too, for `block.using(...)`.
    expect(entries["tenant"]).toEqual({
      schema: "better_supabase",
      api: "api",
      options: {},
    });
  });

  it("emits a typed module next to the main generated module", () => {
    const config = resolveConfig(
      { output: "app/lib/db/generated.ts", blocks: ["tenant", "attachments"] },
      "/project",
    );
    const file = emitBlockConfig(config, { runtimeImport: "better-supabase" });
    expect(file?.path).toBe("app/lib/db/blocks.generated.ts");
    expect(blockConfigPath(config)).toBe("app/lib/db/blocks.generated.ts");
    expect(file?.contents).toContain(
      'import type { GeneratedBlocks } from "better-supabase/blocks";',
    );
    expect(file?.contents).toContain(
      `  attachments: {
    schema: "better_supabase",
    options: {
      requireScan: true,
    },
  },`,
    );
  });

  it("writes nothing when the config installs no blocks", () => {
    expect(emitBlockConfig(resolveConfig({}, "/project"))).toBeUndefined();
  });
});
