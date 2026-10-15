import { toStandardJsonSchema } from "@valibot/to-json-schema";
import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { resolveConfig, resolveJsonSchema } from "../../src/config/index.ts";
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
      outputs: [{ format: "openapi", output: "openapi.json" }],
      failOn: "error",
    });
  });

  it("reads the deprecated openapi key as an alias", () => {
    expect(
      resolveConfig(
        // oxlint-disable-next-line typescript/no-deprecated -- the alias under test
        { openapi: { entry: "api.ts", output: "docs/openapi.json" } },
        "/app",
      ).specs,
    ).toEqual({
      entry: "api.ts",
      outputs: [{ format: "openapi", output: "docs/openapi.json" }],
      failOn: "error",
    });
  });

  it("prefers specs over openapi", () => {
    const outputs = [{ format: "asyncapi" }] as const;
    expect(
      resolveConfig(
        {
          // oxlint-disable-next-line typescript/no-deprecated -- the alias under test
          openapi: { entry: "old.ts" },
          specs: { entry: "new.ts", outputs, failOn: "warning" },
        },
        "/app",
      ).specs,
    ).toEqual({ entry: "new.ts", outputs, failOn: "warning" });
  });
});

describe("resolveConfig access model", () => {
  it("defaults the access model to provider when authorization is set", () => {
    const listed = resolveConfig(
      { authorization: stubProvider, sql: { modules: ["tenant", "access"] } },
      "/app",
    ).sql;
    expect(listed.modules.access?.model).toBe("provider");
    expect(listed.moduleNames).toEqual(["tenant", "access"]);
    const keyed = resolveConfig(
      {
        authorization: stubProvider,
        sql: { modules: { access: { idType: "uuid" } } },
      },
      "/app",
    ).sql.modules.access;
    expect(keyed).toEqual({ idType: "uuid", model: "provider" });
  });

  it("keeps an explicit model, and roles without a provider", () => {
    expect(
      resolveConfig(
        {
          authorization: stubProvider,
          sql: { modules: { access: { model: "roles" } } },
        },
        "/app",
      ).sql.modules.access?.model,
    ).toBe("roles");
    expect(
      resolveConfig({ sql: { modules: ["access"] } }, "/app").sql.modules
        .access,
    ).toBeUndefined();
    expect(
      resolveConfig(
        { authorization: stubProvider, sql: { modules: ["tenant"] } },
        "/app",
      ).sql.modules,
    ).toEqual({});
  });
});

describe("resolveConfig sql defaults", () => {
  it("gives every module sql.schema and sql.api unless it sets its own", () => {
    const sql = resolveConfig(
      {
        sql: {
          schema: "app",
          api: "api",
          modules: {
            comments: {},
            settings: { schema: "settings", api: "public_api" },
            jobs: { api: false },
          },
        },
      },
      "/app",
    ).sql;
    expect(sql.modules).toEqual({
      comments: { schema: "app", api: "api" },
      settings: { schema: "settings", api: "public_api" },
      jobs: { schema: "app", api: false },
    });
  });

  it("applies the defaults to a module list", () => {
    const sql = resolveConfig(
      { sql: { api: "api", modules: ["tags"] } },
      "/app",
    ).sql;
    expect(sql.modules).toEqual({ tags: { api: "api" } });
    expect(sql.moduleNames).toEqual(["tags"]);
  });
});
