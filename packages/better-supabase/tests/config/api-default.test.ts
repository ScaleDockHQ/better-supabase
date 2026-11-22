import { describe, expect, it } from "vitest";

import { apiMatches, suggestSqlApi } from "../../src/config/api-default.ts";
import { resolveConfig } from "../../src/config/index.ts";

describe("apiMatches", () => {
  it("matches the same schema as a string or an object without functions", () => {
    expect(apiMatches("api", "api")).toBe(true);
    expect(apiMatches({ schema: "api" }, "api")).toBe(true);
  });

  it("does not match another schema, false, nothing or a function list", () => {
    expect(apiMatches("other", "api")).toBe(false);
    expect(apiMatches(false, "api")).toBe(false);
    expect(apiMatches(undefined, "api")).toBe(false);
    expect(apiMatches({ schema: "api", functions: ["a"] }, "api")).toBe(false);
  });
});

describe("suggestSqlApi", () => {
  it("names the schema most blocks share and the blocks without an entry", () => {
    expect(
      suggestSqlApi(
        {
          tasks: "api",
          notes: { schema: "api" },
          labels: "api",
          tags: undefined,
        },
        undefined,
      ),
    ).toEqual({
      schema: "api",
      drop: ["tasks", "notes", "labels"],
      disable: ["tags"],
    });
  });

  it("leaves a block with another schema, a function list or false alone", () => {
    const found = suggestSqlApi(
      {
        a: "api",
        b: "api",
        c: "api",
        d: "other",
        e: { schema: "api", functions: ["f"] },
        f: false,
      },
      undefined,
    );

    expect(found).toBeUndefined();
  });

  it("suggests nothing when half or fewer agree, one block agrees or sql.api is set", () => {
    expect(
      suggestSqlApi(
        { a: "api", b: "api", c: undefined, d: undefined },
        undefined,
      ),
    ).toBeUndefined();
    expect(suggestSqlApi({ a: "api" }, undefined)).toBeUndefined();
    expect(suggestSqlApi({ a: "api", b: "api" }, "api")).toBeUndefined();
  });

  it("is read from the resolved config", () => {
    const config = resolveConfig(
      { blocks: { tasks: { api: "api" }, notes: { api: { schema: "api" } } } },
      "/project",
    );

    expect(
      suggestSqlApi(config.blockApis, config.sql.blockDefaults?.api),
    ).toEqual({ schema: "api", drop: ["tasks", "notes"], disable: [] });
  });
});

describe("restated api entries", () => {
  it("lists an object form without functions that repeats sql.api", () => {
    const config = resolveConfig(
      {
        database: { sql: { api: "api" } },
        blocks: {
          tasks: { api: { schema: "api" } },
          notes: { api: { schema: "api", functions: ["x"] } },
        },
      },
      "/project",
    );

    expect(config.restatedDefaults).toEqual([{ block: "tasks", key: "api" }]);
  });
});
