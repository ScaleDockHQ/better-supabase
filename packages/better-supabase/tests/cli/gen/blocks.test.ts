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

  it("writes the function names the tenant name and blocks.<name>.functions give", () => {
    const config = resolveConfig(
      {
        blocks: {
          tenant: { entities: { organization: "workspace" } },
          organizations: {},
          tags: { functions: { create_tag: "make_tag" } },
          access: {
            model: "custom",
            functions: { can: "public.can({scope}, {id}, {permission})" },
          },
        },
      },
      "/project",
    );

    const entries = blockConfigEntries(config);
    expect(entries["organizations"]?.naming).toEqual({ tenant: "workspace" });
    expect(entries["tags"]?.naming).toEqual({
      tenant: "workspace",
      functions: { create_tag: "make_tag" },
    });
    expect(entries["access"]?.naming).toEqual({ tenant: "workspace" });

    const plain = blockConfigEntries(
      resolveConfig({ blocks: ["tags"] }, "/project"),
    );

    expect(plain["tags"]).not.toHaveProperty("naming");
  });

  it("leaves out tenant and access in user scope", () => {
    const entries = blockConfigEntries(
      resolveConfig({ sql: { scope: "user" }, blocks: ["tags"] }, "/project"),
    );

    expect(Object.keys(entries)).toContain("tags");
    expect(Object.keys(entries)).not.toContain("tenant");
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

  it("declares the events app tables emit", () => {
    const config = resolveConfig(
      {
        blocks: { tenant: {}, outbox: {} },
        appTables: {
          tasks: { subject: { type: "task" }, events: true },
          notes: { events: { on: ["deleted"] } },
          files: {},
        },
      },
      "/project",
    );

    const contents =
      emitBlockConfig(config, { runtimeImport: "better-supabase" })?.contents ??
      "";

    expect(contents).toContain(
      'import {\n  type AppTableEventData,\n  defineEvents,\n  event,\n  type GeneratedBlocks,\n} from "better-supabase/blocks";',
    );
    expect(contents).toContain(
      'export const appTableEvents = defineEvents({\n  "task.created": event<AppTableEventData>(),\n  "task.updated": event<AppTableEventData>(),\n  "task.deleted": event<AppTableEventData>(),\n  "notes.deleted": event<AppTableEventData>(),\n});',
    );
    expect(contents).toContain('  "notes.deleted": true,\n} as const;');
  });

  it("writes nothing when the config installs no blocks", () => {
    expect(emitBlockConfig(resolveConfig({}, "/project"))).toBeUndefined();
  });
});
