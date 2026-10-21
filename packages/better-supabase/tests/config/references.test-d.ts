import { describe, expectTypeOf, it } from "vitest";

import type {
  AppTableNames,
  BlockTableReference,
  RoleNames,
} from "../../src/config/references.ts";

import { defineConfig } from "../../src/config/resolve.ts";

describe("defineConfig", () => {
  it("returns the literal config", () => {
    const config = defineConfig({
      blocks: { "work-items": { entities: { work_item: "task" } } },
    });

    expectTypeOf(
      config.blocks["work-items"].entities.work_item,
    ).toEqualTypeOf<"task">();
  });

  it("types app table references to block tables and app tables", () => {
    defineConfig({
      appTables: {
        notes: {
          columns: {
            item: {
              type: "uuid",
              references: { block: "work-items", table: "items" },
            },
            parent: { type: "uuid", references: { table: "notes" } },
          },
        },
      },
    });

    defineConfig({
      appTables: {
        notes: {
          columns: {
            item: {
              type: "uuid",
              // @ts-expect-error -- work-items has no table "itemz".
              references: { block: "work-items", table: "itemz" },
            },
          },
        },
      },
    });

    defineConfig({
      appTables: {
        notes: {
          columns: {
            // @ts-expect-error -- "nots" is not an app table.
            parent: { type: "uuid", references: { table: "nots" } },
          },
        },
      },
    });
  });

  it("types the roles other blocks name from blocks.access.roles", () => {
    defineConfig({
      blocks: {
        access: { roles: { owner: ["*"], member: [] } },
        sso: {
          options: { defaultRole: "member", roleOrder: ["owner", "member"] },
        },
      },
    });

    defineConfig({
      blocks: {
        access: { roles: { owner: ["*"], member: [] } },
        // @ts-expect-error -- "viewer" is not a declared role.
        sso: { options: { defaultRole: "viewer" } },
      },
    });

    defineConfig({ blocks: { sso: { options: { defaultRole: "anything" } } } });
  });

  it("suggests bucket names in storagePaths", () => {
    defineConfig({
      buckets: { avatars: { path: "{userId}/avatar" } },
      storagePaths: { "profiles.avatar": "avatars", "files.path": "legacy" },
    });
  });
});

describe("reference types", () => {
  it("names the app tables of a literal config", () => {
    expectTypeOf<
      AppTableNames<{ appTables: { notes: object } }>
    >().toEqualTypeOf<"notes" | "auth.users">();
    expectTypeOf<AppTableNames<object>>().toEqualTypeOf<string>();
  });

  it("names the declared roles", () => {
    expectTypeOf<
      RoleNames<{ blocks: { access: { roles: { owner: []; guest: [] } } } }>
    >().toEqualTypeOf<"owner" | "guest">();
    expectTypeOf<RoleNames<object>>().toEqualTypeOf<string>();
  });

  it("pairs each block with its own tables", () => {
    expectTypeOf<{
      block: "work-items";
      table: "items";
    }>().toExtend<BlockTableReference>();
    expectTypeOf<{
      block: "work-items";
      table: "contacts";
    }>().not.toExtend<BlockTableReference>();
  });
});
