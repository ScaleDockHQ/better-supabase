import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import type { DoctorContext } from "../../src/cli/doctor/rules.ts";

import { parseSnapshot } from "../../src/cli/commands/snapshot.ts";
import { RULES, runRules } from "../../src/cli/doctor/rules.ts";
import { renderFiles } from "../../src/cli/gen/render.ts";
import {
  moduleRefOf,
  withModuleSchemas,
} from "../../src/cli/module-schemas.ts";
import { resolveConfig } from "../../src/config/index.ts";
import { standardSchema } from "../../src/generators/standard-schema.ts";
import { moduleLayout } from "../../src/sql/layout.ts";
import { snapshotFixture } from "./fixtures/library.ts";
import { loadFixtureSnapshot } from "./fixtures/render.ts";

const document = { type: "object", properties: { theme: { type: "string" } } };

const schemasModule = `
const standard = (document) => ({
  "~standard": {
    version: 1,
    vendor: "test",
    validate: (value) => ({ value }),
    jsonSchema: { input: () => document },
  },
});

export const metadata = standard(${JSON.stringify(document)});
export const theme = standard({ type: "string", enum: ["light", "dark"] });
export const notASchema = 1;
`;

let dir: string | undefined;

afterEach(async () => {
  if (dir !== undefined) {
    await rm(dir, { recursive: true, force: true });
    dir = undefined;
  }
});

async function project(): Promise<string> {
  dir = await mkdtemp(join(tmpdir(), "bsb-module-schemas-"));
  await mkdir(join(dir, "src"), { recursive: true });
  await writeFile(join(dir, "src", "schemas.ts"), schemasModule);

  return dir;
}

describe("withModuleSchemas", () => {
  it("loads a reference in gen.json and remembers where it came from", async () => {
    const root = await project();

    const config = await withModuleSchemas(
      resolveConfig(
        {
          gen: {
            json: {
              "customers.metadata": { schema: "./src/schemas.ts#metadata" },
            },
          },
        },
        root,
      ),
    );

    const loaded = config.json["customers.metadata"]?.schema;

    expect(loaded).toHaveProperty("~standard");
    expect(moduleRefOf(loaded)).toBe("./src/schemas.ts#metadata");
  });

  it("gives the SQL layout the JSON Schema of the export", async () => {
    const root = await project();

    const config = await withModuleSchemas(
      resolveConfig(
        {
          gen: {
            json: {
              "customers.metadata": { schema: "./src/schemas.ts#metadata" },
            },
          },
        },
        root,
      ),
    );

    expect(moduleLayout(config).jsonSchemas).toEqual([
      { table: "customers", column: "metadata", schema: document },
    ]);
  });

  it("types the column from the export without an import or type", async () => {
    const root = await project();

    const config = await withModuleSchemas(
      resolveConfig(
        {
          gen: {
            file: "src/db/generated.ts",
            json: {
              "customers.metadata": { schema: "./src/schemas.ts#metadata" },
            },
          },
        },
        root,
      ),
    );

    const main = (
      await renderFiles(config, await loadFixtureSnapshot(), {
        extensions: false,
      })
    ).find((file) => file.path === "src/db/generated.ts")?.contents;

    expect(main).toContain("StandardSchemaV1.InferOutput<typeof metadata>");
    expect(main).toContain('import type { metadata } from "../schemas.ts";');
  });

  it("keeps an inline JSON Schema as it is", async () => {
    const root = await project();

    const config = await withModuleSchemas(
      resolveConfig(
        {
          gen: {
            json: { "customers.metadata": { type: "Meta", schema: document } },
          },
        },
        root,
      ),
    );

    expect(config.json["customers.metadata"]?.schema).toBe(document);
  });

  it("loads references in the settings schemas, per scope", async () => {
    const root = await project();

    const config = await withModuleSchemas(
      resolveConfig(
        {
          blocks: {
            settings: {
              options: {
                schemas: { user: { theme: "./src/schemas.ts#theme" } },
              },
            },
          },
        },
        root,
      ),
    );

    const schemas = config.blocks["settings"]?.options?.["schemas"] as {
      user: Record<string, unknown>;
    };

    expect(moduleRefOf(schemas.user["theme"])).toBe("./src/schemas.ts#theme");

    const own = config.instances["settings"]?.config.options?.["schemas"] as
      | typeof schemas
      | undefined;

    expect(own?.user["theme"]).toHaveProperty("~standard");
  });

  it("names the key when the export is missing", async () => {
    const root = await project();

    await expect(
      withModuleSchemas(
        resolveConfig(
          {
            gen: {
              json: {
                "customers.metadata": { schema: "./src/schemas.ts#missing" },
              },
            },
          },
          root,
        ),
      ),
    ).rejects.toThrow(
      /customers\.metadata.*does not export a schema named missing/u,
    );

    await expect(
      withModuleSchemas(
        resolveConfig(
          {
            gen: {
              json: {
                "customers.metadata": { schema: "./src/schemas.ts#notASchema" },
              },
            },
          },
          root,
        ),
      ),
    ).rejects.toThrow(/does not export a schema/u);
  });
});

const base = await parseSnapshot(snapshotFixture);

describe("BS704", () => {
  const run = async (root: string, json: Record<string, unknown>) => {
    const context: DoctorContext = {
      config: resolveConfig(
        {
          gen: {
            // SAFETY: the test passes the same shapes the config type allows.
            json: json as never,
            generators: [
              standardSchema({
                json: { "customers.metadata": "./src/schemas.ts#metadata" },
              }),
            ],
          },
        },
        root,
      ),
      snapshot: base,
      configToml: undefined,
      envFiles: [],
      gitignore: "",
      sources: [],
    };

    return runRules(
      context,
      RULES.filter((rule) => rule.code === "BS704"),
    );
  };

  it("points an inline schema at the export that produces it", async () => {
    const root = await project();

    const findings = await run(root, {
      "customers.metadata": { type: "Meta", schema: { ...document } },
    });

    expect(findings).toHaveLength(1);
    expect(findings[0]?.message).toContain('"./src/schemas.ts#metadata"');
  });

  it("stays quiet when no export matches or the config uses a reference", async () => {
    const root = await project();

    expect(
      await run(root, {
        "customers.metadata": { type: "Meta", schema: { type: "number" } },
      }),
    ).toEqual([]);
    expect(
      await run(root, {
        "customers.metadata": { schema: "./src/schemas.ts#metadata" },
      }),
    ).toEqual([]);
    expect(dirname(root)).toBeTruthy();
  });
});
