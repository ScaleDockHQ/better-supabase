import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import {
  OFFICIAL_SCHEMAS,
  officialSchema,
} from "../../../src/cli/spec/schemas.ts";
import { validateDocument } from "../../../src/cli/spec/validate.ts";

const info = { title: "CRM", version: "1.0.0" };

const VALID: Readonly<Record<string, unknown>> = {
  "openapi@3.0": { openapi: "3.0.4", info, paths: {} },
  "openapi@3.1": { openapi: "3.1.2", info, paths: {} },
  "openapi@3.2": { openapi: "3.2.0", info, paths: {} },
  "asyncapi@3.0": { asyncapi: "3.0.0", info },
  "asyncapi@3.1": { asyncapi: "3.1.0", info },
  "arazzo@1.0": {
    arazzo: "1.0.1",
    info,
    sourceDescriptions: [{ name: "crm", url: "openapi.json", type: "openapi" }],
    workflows: [
      {
        workflowId: "list",
        steps: [{ stepId: "list", operationId: "listCustomers" }],
      },
    ],
  },
  "arazzo@1.1": {
    arazzo: "1.1.0",
    info,
    sourceDescriptions: [{ name: "crm", url: "openapi.json", type: "openapi" }],
    workflows: [
      {
        workflowId: "list",
        steps: [{ stepId: "list", operationId: "listCustomers" }],
      },
    ],
  },
};

describe("validateDocument", () => {
  it.each([...OFFICIAL_SCHEMAS.keys()])(
    "accepts a minimal %s document",
    async (key) => {
      const [format = "", version = ""] = key.split("@");
      expect(await validateDocument(format, version, VALID[key])).toEqual([]);
    },
  );

  it("reports where a document breaks the schema", async () => {
    const diagnostics = await validateDocument("openapi", "3.1", {
      openapi: "3.1.2",
      info: { title: "CRM" },
      paths: {},
    });
    expect(diagnostics[0]).toMatchObject({
      code: "schema-invalid",
      severity: "error",
      pointer: "/info",
    });
  });

  it("rejects a broken AsyncAPI and Arazzo document", async () => {
    expect(
      await validateDocument("asyncapi", "3.0", { asyncapi: "3.0.0" }),
    ).not.toEqual([]);
    expect(
      await validateDocument("arazzo", "1.0", { arazzo: "1.0.1", info }),
    ).not.toEqual([]);
  });

  it("validates OpenAPI 3.0 through the converted draft-04 schema", async () => {
    const diagnostics = await validateDocument("openapi", "3.0", {
      openapi: "3.0.4",
      info,
      paths: {
        "/x": { get: { responses: { "200": { description: "ok" } }, nope: 1 } },
      },
    });
    expect(
      diagnostics.some((diagnostic) => diagnostic.code === "schema-invalid"),
    ).toBe(true);
  });

  it("caps the error list", async () => {
    const paths = Object.fromEntries(
      Array.from({ length: 80 }, (_, index) => [
        `/p${index}`,
        { get: { responses: 1 } },
      ]),
    );
    const diagnostics = await validateDocument("openapi", "3.1", {
      openapi: "3.1.2",
      info,
      paths,
    });
    expect(diagnostics).toHaveLength(51);
    expect(diagnostics.at(-1)?.message).toMatch(/more schema errors not shown/);
  });

  it("says when no schema is bundled", async () => {
    expect(officialSchema("openapi", "3.3-preview")).toBeUndefined();
    expect(await validateDocument("graphql", "1", {})).toEqual([
      expect.objectContaining({ code: "schema-unavailable", severity: "info" }),
    ]);
  });
});

describe("vendored schemas", () => {
  it("match the copies the standards tests pin in SOURCES.md", async () => {
    const vendored = join(import.meta.dirname, "../../../src/cli/spec/schemas");
    const pinned = join(import.meta.dirname, "../../standards/schemas");
    const files = (await readdir(vendored)).filter((file) =>
      file.endsWith(".json"),
    );
    expect(files).toHaveLength(OFFICIAL_SCHEMAS.size);
    for (const file of files) {
      const [copy, original] = await Promise.all([
        readFile(join(vendored, file), "utf8"),
        readFile(join(pinned, file), "utf8"),
      ]);
      expect({ file, same: copy === original }).toEqual({ file, same: true });
    }
  });
});
