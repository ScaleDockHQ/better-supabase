import { describe, expectTypeOf, it } from "vitest";

import type { AuthorizationProvider } from "../../src/config/authorization.ts";
import type {
  BlockTableReference,
  RoleNames,
} from "../../src/config/references.ts";

import { defineConfig } from "../../src/config/resolve.ts";

describe("defineConfig", () => {
  it("returns the literal config", () => {
    const config = defineConfig({
      blocks: { tasks: { names: { task: "task" } } },
    });

    expectTypeOf(config.blocks.tasks.names.task).toEqualTypeOf<"task">();
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

  it("types permission keys from a typed provider", () => {
    const provider = {
      apiVersion: 1,
      name: "typed",
      scopes: [{ name: "organization", idType: "uuid" }],
      tenantScope: "organization",
      functions: {
        idsWith: "a.ids({permission})",
        isPlatform: "a.is({permission})",
      },
      permissions: [{ key: "tasks.read" }, { key: "tasks.write" }],
    } as const satisfies AuthorizationProvider<"tasks.read" | "tasks.write">;

    const typed: AuthorizationProvider<"tasks.read" | "tasks.write"> = provider;

    defineConfig({
      auth: { authorization: typed },
      blocks: {
        tasks: { permissions: { read: "tasks.read" } },
        permissions: { roles: { member: ["tasks.read"] } },
      },
      recordTypes: {
        task: { table: "public.tasks", permissions: { read: "tasks.read" } },
      },
    });

    defineConfig({
      auth: { authorization: typed },
      // @ts-expect-error -- "tasks.raed" is not a key the provider declares.
      blocks: { tasks: { permissions: { read: "tasks.raed" } } },
    });

    defineConfig({
      auth: { authorization: typed },
      blocks: { permissions: { roles: { member: ["tasks.read"] } } },
      // @ts-expect-error -- "tasks.delete" is not a key the provider declares.
      recordTypes: {
        task: {
          table: "public.tasks",
          permissions: { write: { key: "tasks.delete" } },
        },
      },
    });

    defineConfig({
      blocks: { tasks: { permissions: { read: "anything.goes" } } },
    });
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
