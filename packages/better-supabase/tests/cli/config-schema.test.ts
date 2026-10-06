import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { configIssues } from "../../src/cli/config-schema.ts";
import { loadConfig } from "../../src/cli/config.ts";

const repo = join(import.meta.dirname, "../../../..");

describe("configIssues", () => {
  it("accepts a full config, generators included", () => {
    expect(
      configIssues({
        casing: "camel",
        codecs: { timestamptz: "instant", int8: "bigint" },
        plugins: { tenant: { column: "org_id" }, timestamps: true },
        expose: { notes: ["select"], tags: { anon: ["select"] } },
        tables: {
          audit_logs: { serviceRole: true },
          jobs: { exclude: true },
          invoices: { insertOptional: ["number"] },
        },
        generators: [{ name: "zod", generate: () => [] }],
        doctor: { ignore: ["BS303"], strict: true },
      }),
    ).toEqual([]);
  });

  it("names the key path of every problem", () => {
    expect(
      configIssues({
        casing: "pascal",
        codecs: { timestamptz: "date" },
        generators: [{ name: "zod" }],
        typo: true,
      }),
    ).toEqual([
      expect.stringMatching(/^casing: Invalid type/),
      expect.stringMatching(/^codecs\.timestamptz: Invalid type/),
      "generators.0: must be a generator: { name, generate(input) }",
      expect.stringMatching(/^typo: Invalid key/),
    ]);
  });

  it("takes the access keys only under sql.modules.access", () => {
    expect(
      configIssues({
        sql: {
          modules: {
            access: { model: "catalog", activeTenant: "claim" },
            organizations: { mode: "adopt", options: { ownerRole: "owner" } },
          },
        },
      }),
    ).toEqual([]);
    expect(
      configIssues({
        sql: { modules: { organizations: { model: "catalog" } } },
      }),
    ).toEqual([
      expect.stringMatching(/^sql\.modules\.organizations\.model: Invalid key/),
    ]);
  });
});

describe("committed configs", () => {
  it.each([
    "apps/examples/nextjs",
    "apps/examples/orpc-api",
    "apps/examples/hono-api",
    "apps/examples/vite-react",
    "apps/examples/mcp",
    "apps/examples/edge",
    "tests/validation-crm",
    "tests/validation-monorepo",
    "tests/validation-request-context",
    "tests/types/shared",
  ])("%s loads", async (dir) => {
    await expect(loadConfig(join(repo, dir))).resolves.toMatchObject({
      root: join(repo, dir),
    });
  });
});
