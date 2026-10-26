import { describe, expectTypeOf, it } from "vitest";

import type {
  BlockTableReference,
  RoleNames,
} from "../../src/config/references.ts";

import { defineConfig } from "../../src/config/resolve.ts";

describe("defineConfig", () => {
  it("returns the literal config", () => {
    const config = defineConfig({
      blocks: { tasks: { names: { work_item: "task" } } },
    });

    expectTypeOf(config.blocks.tasks.names.work_item).toEqualTypeOf<"task">();
  });

  it("types the roles other blocks name from blocks.permissions.roles", () => {
    defineConfig({
      blocks: {
        permissions: { roles: { owner: ["*"], member: [] } },
        sso: {
          options: { defaultRole: "member", roleOrder: ["owner", "member"] },
        },
      },
    });

    defineConfig({
      blocks: {
        permissions: { roles: { owner: ["*"], member: [] } },
        // @ts-expect-error -- "viewer" is not a declared role.
        sso: { options: { defaultRole: "viewer" } },
      },
    });

    defineConfig({ blocks: { sso: { options: { defaultRole: "anything" } } } });
  });

  it("suggests bucket names in storagePaths", () => {
    defineConfig({
      database: { buckets: { avatars: { path: "{userId}/avatar" } } },
      gen: {
        storagePaths: { "profiles.avatar": "avatars", "files.path": "legacy" },
      },
    });
  });
});

describe("reference types", () => {
  it("names the declared roles", () => {
    expectTypeOf<
      RoleNames<{
        blocks: { permissions: { roles: { owner: []; guest: [] } } };
      }>
    >().toEqualTypeOf<"owner" | "guest">();
    expectTypeOf<RoleNames<object>>().toEqualTypeOf<string>();
  });

  it("pairs each block with its own tables", () => {
    expectTypeOf<{
      block: "tasks";
      table: "items";
    }>().toExtend<BlockTableReference>();
    expectTypeOf<{
      block: "tasks";
      table: "contacts";
    }>().not.toExtend<BlockTableReference>();
  });
});
