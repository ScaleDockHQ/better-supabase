import { readdir, readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";

import type { Snapshot } from "../../src/cli/introspect/types.ts";

import { formatReport } from "../../src/cli/doctor/format.ts";
import { RULES, runRules } from "../../src/cli/doctor/rules.ts";
import { generatorJsonSchema } from "../../src/cli/introspect/typegen.ts";
import { buildManifest } from "../../src/cli/spec/diagnostics.ts";
import { parseToml } from "../../src/cli/supabase-toml.ts";
import { resolveConfig } from "../../src/config/index.ts";
import { snapshotFixture as fixture } from "./fixtures/library.ts";

type Schema = Readonly<Record<string, unknown>>;

const SCHEMAS = new URL(
  "./",
  import.meta.resolve("better-supabase/schemas/config-v1.json"),
);
const load = async (name: string): Promise<Schema> =>
  JSON.parse(await readFile(new URL(name, SCHEMAS), "utf-8")) as Schema;

const typeOf = (value: unknown): string => {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  if (Number.isInteger(value)) return "integer";
  return typeof value;
};

/** Enough of JSON Schema 2020-12 for the shipped schemas: type, enum, const, $ref, properties, additionalProperties, items, oneOf. */
function validate(
  root: Schema,
  schema: Schema,
  value: unknown,
  path: string,
  errors: string[],
): void {
  if (typeof schema["$ref"] === "string") {
    const target = schema["$ref"]
      .replace(/^#\//, "")
      .split("/")
      .reduce<unknown>((node, key) => (node as Schema)[key], root) as Schema;
    validate(root, target, value, path, errors);
  }
  if (Array.isArray(schema["oneOf"])) {
    const matches = (schema["oneOf"] as Schema[]).filter((option) => {
      const inner: string[] = [];
      validate(root, option, value, path, inner);
      return inner.length === 0;
    });
    if (matches.length !== 1)
      errors.push(`${path}: matches ${matches.length} oneOf options`);
  }
  if ("const" in schema && value !== schema["const"])
    errors.push(`${path}: expected ${JSON.stringify(schema["const"])}`);
  if (
    Array.isArray(schema["enum"]) &&
    !(schema["enum"] as unknown[]).includes(value)
  ) {
    errors.push(
      `${path}: ${JSON.stringify(value)} is not one of ${JSON.stringify(schema["enum"])}`,
    );
  }
  if (schema["type"] !== undefined) {
    const types = ([] as unknown[]).concat(schema["type"]);
    const actual = typeOf(value);
    if (
      !types.includes(actual) &&
      !(actual === "integer" && types.includes("number"))
    ) {
      errors.push(`${path}: expected ${types.join(" | ")}, got ${actual}`);
      return;
    }
  }
  if (typeOf(value) === "object") {
    const object = value as Record<string, unknown>;
    const properties = (schema["properties"] ?? {}) as Record<string, Schema>;
    for (const key of (schema["required"] ?? []) as string[]) {
      if (!(key in object)) errors.push(`${path}: missing ${key}`);
    }
    for (const [key, item] of Object.entries(object)) {
      const additional = schema["additionalProperties"];
      if (properties[key])
        validate(root, properties[key], item, `${path}.${key}`, errors);
      else if (additional === false) errors.push(`${path}: unexpected ${key}`);
      else if (typeof additional === "object" && additional !== null)
        validate(root, additional as Schema, item, `${path}.${key}`, errors);
    }
  }
  if (Array.isArray(value) && schema["items"]) {
    value.forEach((item, index) => {
      validate(
        root,
        schema["items"] as Schema,
        item,
        `${path}[${index}]`,
        errors,
      );
    });
  }
}

async function errorsFor(name: string, value: unknown): Promise<string[]> {
  const schema = await load(name);
  const errors: string[] = [];
  validate(schema, schema, value, "$", errors);
  return errors;
}

describe("shipped JSON Schemas", () => {
  it("have an $id matching their file and are referenced by the code", async () => {
    const files = (await readdir(SCHEMAS)).filter((file) =>
      file.endsWith(".json"),
    );
    expect(files.toSorted((a, b) => a.localeCompare(b))).toEqual([
      "ai-message-v1.json",
      "config-v1.json",
      "doctor-report-v1.json",
      "snapshot-v2.json",
      "spec-manifest-v1.json",
    ]);
    for (const file of files) {
      expect((await load(file))["$id"]).toBe(
        `https://unpkg.com/better-supabase/schemas/${file}`,
      );
    }
  });

  it("describe the fixture snapshot", async () => {
    expect(await errorsFor("snapshot-v2.json", fixture)).toEqual([]);
    const [first] = fixture.extras.tables;
    const broken = {
      ...fixture,
      extras: {
        ...fixture.extras,
        tables: [
          {
            ...first,
            foreignKeys: [
              { name: "fk", onDelete: "explode", onUpdate: "cascade" },
            ],
            extra: 1,
          },
        ],
      },
    };
    expect(await errorsFor("snapshot-v2.json", broken)).toEqual([
      '$.extras.tables[0].foreignKeys[0].onDelete: "explode" is not one of ["no action","restrict","cascade","set null","set default"]',
      "$.extras.tables[0]: unexpected extra",
    ]);
  });

  it("embed the postgrest-typegen metadata schema unchanged", async () => {
    const schema = (await load("snapshot-v2.json")) as {
      $defs: { generator: unknown };
    };
    expect(schema.$defs.generator).toEqual(await generatorJsonSchema());
  });

  it("match the snapshot the examples and type tests generate from", async () => {
    const shared = await readFile(
      new URL("../../../../supabase/snapshot.json", import.meta.url),
      "utf-8",
    );
    expect(JSON.parse(shared)).toEqual(fixture);
  });

  it("describe doctor reports", async () => {
    const snapshot = structuredClone(fixture) as unknown as {
      generator: { tables: { schema: string; rls_enabled: boolean }[] };
    };
    snapshot.generator.tables.find(
      (table) => table.schema === "public",
    )!.rls_enabled = false;
    const context = {
      config: resolveConfig({}, "/project"),
      snapshot: snapshot as unknown as Snapshot,
      configToml: {
        path: "supabase/config.toml",
        dir: "supabase",
        text: "[auth]\njwt_expiry = 7200\n",
        document: parseToml("[auth]\njwt_expiry = 7200\n"),
        parser: "smol-toml" as const,
      },
      envFiles: [{ path: ".env", text: "SUPABASE_SECRET_KEY=x\n" }],
      gitignore: "",
      sources: [],
    };
    const findings = await runRules(
      context,
      RULES.filter((rule) => rule.code !== "BS303"),
    );
    expect(findings.length).toBeGreaterThan(2);
    const report = JSON.parse(
      formatReport(findings, {
        format: "json",
        rules: RULES,
        version: "0.0.0",
        fallbackFile: "package.json",
      }),
    ) as unknown;
    expect(await errorsFor("doctor-report-v1.json", report)).toEqual([]);
  });

  it("describe a full config", async () => {
    const config = {
      $schema: "https://unpkg.com/better-supabase/schemas/config-v1.json",
      source: { snapshot: "supabase/snapshot.json" },
      schemas: ["public"],
      casing: "camel",
      output: "src/lib/supabase/generated.ts",
      postgrestVersion: "13",
      tables: { audit_logs: { serviceRole: true } },
      doctor: { ignore: ["BS204"], strict: true, sources: ["app/**/*.tsx"] },
      specs: {
        entry: "src/lib/api.ts",
        outputs: [
          { format: "openapi", version: "3.2", ui: "scalar" },
          { format: "asyncapi", output: "asyncapi.yaml", overlays: ["o.yaml"] },
        ],
        failOn: "warning",
      },
    };
    expect(await errorsFor("config-v1.json", config)).toEqual([]);
    expect(
      await errorsFor("config-v1.json", { ...config, casing: "kebab" }),
    ).toHaveLength(1);
  });

  it("describe the CLI keys and the environment blocks", async () => {
    const config = {
      gen: { tasks: ["types", "sql", "spec"], watchInterval: 1000 },
      env: { output: ".env.development.local", prefix: "NEXT_PUBLIC_" },
      doctor: { only: ["BS100"], format: "sarif", output: "doctor.sarif" },
      scaffold: {
        api: { framework: "hono", tables: ["notes"], basePath: "/v1" },
      },
      integrations: ["next", "client"],
      skills: { agents: ["cursor"] },
      keys: { output: "supabase/keys.json" },
      specs: { manifest: "spec-manifest.json" },
      $env: { staging: { doctor: { strict: true } } },
      $ci: { gen: { tasks: ["types"] } },
    };
    expect(await errorsFor("config-v1.json", config)).toEqual([]);
    expect(
      await errorsFor("config-v1.json", { $ci: { gen: { tasks: ["lint"] } } }),
    ).toHaveLength(1);
    expect(
      await errorsFor("config-v1.json", { $env: { staging: { $ci: {} } } }),
    ).toHaveLength(1);
  });

  it("describe the spec diagnostics manifest", async () => {
    const manifest = buildManifest(
      [
        {
          format: "openapi",
          version: "3.1",
          pin: "3.1.2",
          path: "openapi.json",
          sha256: "0".repeat(64),
          status: "written",
          cached: false,
          diagnostics: [
            {
              code: "preview-version",
              severity: "warning",
              message: "m",
              pointer: "/",
            },
          ],
        },
      ],
      "error",
      true,
    );
    expect(manifest.summary).toEqual({ error: 0, warning: 1, info: 0 });
    expect(await errorsFor("spec-manifest-v1.json", manifest)).toEqual([]);
    expect(
      await errorsFor("spec-manifest-v1.json", { ...manifest, failOn: "loud" }),
    ).toHaveLength(1);
  });
});
