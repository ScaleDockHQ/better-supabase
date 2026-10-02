import addFormats from "ajv-formats";
import Ajv2020 from "ajv/dist/2020.js";
import { SPEC_PINS } from "better-supabase";
import { CONFIG_SCHEMA_URL, resolveConfig } from "better-supabase/config";
import { readdir, readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";

import { formatReport } from "../../src/doctor/format.ts";
import { RULES, runRules } from "../../src/doctor/rules.ts";
import { parseTomlSubset } from "../../src/supabase-toml.ts";
import {
  readJsonFixture,
  snapshotFixture as fixture,
} from "../fixtures/library.ts";
import { metaSchema2020, problems } from "./validator.ts";

const DIALECT = "https://json-schema.org/draft/2020-12/schema";
const shipped = new URL(
  "./",
  import.meta.resolve("better-supabase/schemas/config-v1.json"),
);

async function shippedSchemas(): Promise<Map<string, Record<string, unknown>>> {
  const out = new Map<string, Record<string, unknown>>();
  for (const file of await readdir(shipped))
    out.set(
      file,
      JSON.parse(await readFile(new URL(file, shipped), "utf8")) as Record<
        string,
        unknown
      >,
    );
  return out;
}

/** A validator with every shipped schema registered under its `$id`. */
async function shippedValidator() {
  const ajv = new Ajv2020({ strict: true, allErrors: true });
  addFormats(ajv);
  for (const schema of (await shippedSchemas()).values()) ajv.addSchema(schema);
  return ajv;
}

describe("JSON Schema 2020-12", () => {
  it("SPEC_PINS.jsonSchema names the dialect every schema declares", () => {
    expect(SPEC_PINS.jsonSchema).toBe("2020-12");
    expect(DIALECT).toContain(SPEC_PINS.jsonSchema);
  });

  it("every shipped schema declares the 2020-12 dialect and is valid against its meta-schema", async () => {
    const meta = metaSchema2020();
    for (const [file, schema] of await shippedSchemas()) {
      expect([file, schema["$schema"], problems(meta, schema)]).toEqual([
        file,
        DIALECT,
        [],
      ]);
    }
  });

  it("every shipped schema compiles in strict mode (no unknown keywords or formats)", async () => {
    const ajv = await shippedValidator();
    for (const schema of (await shippedSchemas()).values())
      expect(ajv.getSchema(String(schema["$id"]))).toBeTypeOf("function");
  });

  it("the generated table schemas are valid 2020-12 schemas", () => {
    // SAFETY: the jsonSchema() generator writes an object with $schema.
    const generatedSchema = readJsonFixture("generated-camel.schema.json") as {
      $schema: string;
    };
    expect(generatedSchema.$schema).toBe(DIALECT);
    expect(problems(metaSchema2020(), generatedSchema)).toEqual([]);
  });

  it("config, snapshot and doctor report documents validate against the schemas they name in `$schema`", async () => {
    const ajv = await shippedValidator();
    const check = (document: Record<string, unknown>) => {
      const validate = ajv.getSchema(String(document["$schema"]));
      expect(validate).toBeTypeOf("function");
      validate!(document);
      return validate!.errors ?? [];
    };
    expect(
      check({
        $schema: CONFIG_SCHEMA_URL,
        schemas: ["public"],
        casing: "camel",
      }),
    ).toEqual([]);
    expect(check({ $schema: CONFIG_SCHEMA_URL, casing: "kebab" })).not.toEqual(
      [],
    );
    expect(check(fixture as unknown as Record<string, unknown>)).toEqual([]);

    const context = {
      config: resolveConfig({}, "/project"),
      snapshot: fixture,
      configToml: {
        path: "supabase/config.toml",
        text: "[auth]\njwt_expiry = 7200\n",
        document: parseTomlSubset("[auth]\njwt_expiry = 7200\n"),
        parser: "builtin" as const,
      },
      envFiles: [{ path: ".env", text: "SUPABASE_SECRET_KEY=x\n" }],
      gitignore: "",
      sources: [],
    };
    const findings = await runRules(
      context,
      RULES.filter((rule) => rule.code !== "BS303"),
    );
    const report = JSON.parse(
      formatReport(findings, {
        format: "json",
        rules: RULES,
        version: "0.0.0",
        fallbackFile: "package.json",
      }),
    ) as Record<string, unknown>;
    expect(check(report)).toEqual([]);
  });
});
