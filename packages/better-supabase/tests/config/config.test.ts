import { toStandardJsonSchema } from "@valibot/to-json-schema";
import * as v from "valibot";
import { describe, expect, it } from "vitest";

import type { BetterSupabaseConfig } from "../../src/config/index.ts";

import {
  flattenConfig,
  groupConfig,
  resolveConfig,
  resolveJsonSchema,
} from "../../src/config/index.ts";
import { stubProvider } from "../fixtures/authorization-provider.ts";

describe("resolveJsonSchema", () => {
  const tuple = toStandardJsonSchema(v.tuple([v.string()]));

  it("converts a Standard Schema for 2020-12 by default", () => {
    expect(resolveJsonSchema(tuple)).toMatchObject({
      $schema: "https://json-schema.org/draft/2020-12/schema",
      prefixItems: [{ type: "string" }],
    });
  });

  it("converts for another target", () => {
    expect(resolveJsonSchema(tuple, "draft-07")).toMatchObject({
      $schema: "http://json-schema.org/draft-07/schema#",
      items: [{ type: "string" }],
    });
  });

  it("returns a JSON Schema object as it is", () => {
    expect(resolveJsonSchema({ type: "array" }, "draft-07")).toEqual({
      type: "array",
    });
  });
});

describe("resolveConfig specs", () => {
  it("defaults to one OpenAPI output", () => {
    expect(resolveConfig({}, "/app").specs).toEqual({
      entry: "src/lib/openapi.ts",
      outputs: [{ format: "openapi", file: "openapi.json" }],
      failOn: "error",
    });
  });

  it("reads specs", () => {
    const outputs = [{ format: "asyncapi" }] as const;
    expect(
      resolveConfig(
        { api: { specs: { entry: "new.ts", outputs, failOn: "warning" } } },
        "/app",
      ).specs,
    ).toEqual({ entry: "new.ts", outputs, failOn: "warning" });
  });
});

describe("resolveConfig access model", () => {
  it("defaults the access model to provider when authorization is set", () => {
    const listed = resolveConfig(
      {
        auth: { authorization: stubProvider },
        blocks: ["memberships", "permissions"],
      },
      "/app",
    );

    expect(listed.blocks.permissions?.model).toBe("provider");
    expect(listed.blockNames).toEqual(["memberships", "permissions"]);

    const keyed = resolveConfig(
      {
        auth: { authorization: stubProvider },
        blocks: { permissions: { idType: "uuid" } },
      },
      "/app",
    ).blocks.permissions;

    expect(keyed).toEqual({ idType: "uuid", model: "provider" });
  });

  it("keeps an explicit model, and roles without a provider", () => {
    expect(
      resolveConfig(
        {
          auth: { authorization: stubProvider },
          blocks: { permissions: { model: "roles" } },
        },
        "/app",
      ).blocks.permissions?.model,
    ).toBe("roles");
    expect(
      resolveConfig({ blocks: ["permissions"] }, "/app").blocks.permissions,
    ).toBeUndefined();
    expect(
      resolveConfig(
        { auth: { authorization: stubProvider }, blocks: ["memberships"] },
        "/app",
      ).blocks,
    ).toEqual({});
  });
});

describe("resolveConfig sql defaults", () => {
  it("gives every block sql.schema and sql.api unless it sets its own", () => {
    const { blocks } = resolveConfig(
      {
        database: { sql: { schema: "app", api: "api" } },
        blocks: {
          comments: {},
          settings: { schema: "settings", api: "public_api" },
          queue: { api: false },
        },
      },
      "/app",
    );

    expect(blocks).toEqual({
      comments: { schema: "app", api: "api" },
      settings: { schema: "settings", api: "public_api" },
      queue: { schema: "app", api: false },
    });
  });

  it("gives every block sql.ownTablePolicies unless it sets its own", () => {
    const { blocks } = resolveConfig(
      {
        database: { sql: { ownTablePolicies: "app" } },
        blocks: { memberships: {}, webhooks: { ownTablePolicies: "block" } },
      },
      "/app",
    );

    expect(blocks).toEqual({
      memberships: { ownTablePolicies: "app" },
      webhooks: { ownTablePolicies: "block" },
    });
  });

  it("applies the defaults to a block list", () => {
    const { blocks, blockNames } = resolveConfig(
      { database: { sql: { api: "api" } }, blocks: ["tags"] },
      "/app",
    );

    expect(blocks).toEqual({ tags: { api: "api" } });
    expect(blockNames).toEqual(["tags"]);
  });
});

describe("flattenConfig and groupConfig", () => {
  const grouped = {
    database: { schemas: ["public"], sql: { owner: "user" } },
    auth: { tenant: { claim: "app_metadata.org_id", column: "org_id" } },
    gen: {
      casing: "camel",
      tables: { audit: { serviceRole: true } },
      tasks: ["types"],
    },
    tooling: { doctor: { strict: true } },
    recordTypes: { customer: { table: "customers" } },
    adapters: ["next"],
    blocks: {
      teams: { ownership: "custom", owner: "user" },
      memberships: { names: { organization: "workspace" } },
    },
  } satisfies BetterSupabaseConfig;

  it("flattens the groups and renames the keys to the resolved names", () => {
    expect(flattenConfig(grouped)).toEqual({
      schemas: ["public"],
      sql: { scope: "user" },
      claims: { tenant: "app_metadata.org_id" },
      tenant: { column: "org_id" },
      casing: "camel",
      tables: { audit: { serviceRole: true } },
      gen: { tasks: ["types"] },
      doctor: { strict: true },
      recordTypes: { customer: { table: "customers" } },
      adapters: ["next"],
      blocks: {
        teams: { mode: "custom", scope: "user" },
        memberships: { entities: { organization: "workspace" } },
      },
    });
  });

  it("groups a flat config back", () => {
    expect(groupConfig(flattenConfig(grouped))).toEqual(grouped);
  });
});

describe("resolveConfig vector search", () => {
  it("installs the vector-search block for an app with a vectorSearch table", () => {
    const search = { database: { vectorSearch: { chunks: "embedding" } } };

    expect(resolveConfig(search, "/app").blockNames).toContain("vector-search");
    expect(
      resolveConfig({ ...search, blocks: ["vector-search"] }, "/app")
        .blockNames,
    ).toEqual(["vector-search"]);
    expect(resolveConfig({}, "/app").blockNames).not.toContain("vector-search");
  });
});
