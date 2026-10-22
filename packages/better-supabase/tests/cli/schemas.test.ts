import {
  mkdir,
  mkdtemp,
  readdir,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { Snapshot } from "../../src/cli/introspect/types.ts";

import { CLI_ERROR_CODES } from "../../src/cli/core/errors.ts";
import { run } from "../../src/cli/core/run.ts";
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
  if (value === null) {
    return "null";
  }

  if (Array.isArray(value)) {
    return "array";
  }

  if (Number.isInteger(value)) {
    return "integer";
  }

  return typeof value;
};

/**
 * Enough of JSON Schema 2020-12 for the shipped schemas: type, enum, const,
 * $ref, properties, additionalProperties, items, oneOf, anyOf.
 */
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

    if (matches.length !== 1) {
      errors.push(`${path}: matches ${matches.length} oneOf options`);
    }
  }

  if (Array.isArray(schema["anyOf"])) {
    const matches = (schema["anyOf"] as Schema[]).some((option) => {
      const inner: string[] = [];
      validate(root, option, value, path, inner);

      return inner.length === 0;
    });

    if (!matches) {
      errors.push(`${path}: matches no anyOf option`);
    }
  }

  if ("const" in schema && value !== schema["const"]) {
    errors.push(`${path}: expected ${JSON.stringify(schema["const"])}`);
  }

  if (
    Array.isArray(schema["enum"]) &&
    !(schema["enum"] as unknown[]).includes(value)
  ) {
    errors.push(
      `${path}: ${JSON.stringify(value)} is not one of ${JSON.stringify(schema["enum"])}`,
    );
  }

  if (schema["type"] !== undefined) {
    const types: unknown[] = Array.isArray(schema["type"])
      ? schema["type"]
      : [schema["type"]];

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
      if (!(key in object)) {
        errors.push(`${path}: missing ${key}`);
      }
    }

    for (const [key, item] of Object.entries(object)) {
      const additional = schema["additionalProperties"];

      if (properties[key]) {
        validate(root, properties[key], item, `${path}.${key}`, errors);
      } else if (additional === false) {
        errors.push(`${path}: unexpected ${key}`);
      } else if (typeof additional === "object" && additional !== null) {
        validate(root, additional as Schema, item, `${path}.${key}`, errors);
      }
    }
  }

  if (Array.isArray(value) && schema["items"]) {
    for (const [index, item] of value.entries()) {
      validate(
        root,
        schema["items"] as Schema,
        item,
        `${path}[${index}]`,
        errors,
      );
    }
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
      "cli-commands-v1.json",
      "cli-result-v1.json",
      "config-v1.json",
      "design-v1.json",
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

  it("describe the command tree that --help --json prints", async () => {
    const root = await run(["--help", "--json"]);
    expect(root.code).toBe(0);
    expect(
      await errorsFor("cli-commands-v1.json", JSON.parse(root.stdout)),
    ).toEqual([]);

    const gen = JSON.parse((await run(["gen", "--help", "--json"])).stdout);
    expect(await errorsFor("cli-commands-v1.json", gen)).toEqual([]);
    expect(
      gen.commands.map((command: { name: string }) => command.name),
    ).toEqual(["gen"]);
  });

  it.each([
    [["--version", "--json"], 0, "success"],
    [["gen", "--chek", "--json"], 2, "error"],
    [["gne", "--json"], 2, "error"],
    [["skills", "list", "--json"], 0, "success"],
    [["blocks", "list", "--installed", "--json"], 0, "success"],
    [["blocks", "view", "--sql", "mfa", "--json"], 0, "success"],
    [["blocks", "view", "--sql", "--json"], 3, "action_required"],
    [["blocks", "view", "--sql", "nope", "--json"], 2, "error"],
    [["--json"], 2, "error"],
    [["blocks", "--json"], 2, "error"],
  ])("describe the result of %j", async (argv, code, status) => {
    const result = await run(argv);
    const envelope = JSON.parse(result.stdout) as { status: string };

    expect(result.code).toBe(code);
    expect(envelope.status).toBe(status);
    expect(await errorsFor("cli-result-v1.json", envelope)).toEqual([]);
  });

  describe("in a project", () => {
    let dir = "";
    let workspace = "";

    const snapshot = fileURLToPath(
      new URL("fixtures/module-snapshot.json", import.meta.url),
    );

    beforeAll(async () => {
      dir = await mkdtemp(join(tmpdir(), "better-supabase-schemas-"));
      await writeFile(
        join(dir, "package.json"),
        JSON.stringify({ name: "app", dependencies: { next: "16.0.0" } }),
      );
      await writeFile(join(dir, "better-supabase.config.json"), "{}\n");
      workspace = await mkdtemp(join(tmpdir(), "better-supabase-schemas-ws-"));
      await mkdir(join(workspace, "apps/web"), { recursive: true });
      await writeFile(join(workspace, "package.json"), '{"name":"root"}');
      await writeFile(
        join(workspace, "pnpm-workspace.yaml"),
        "packages:\n  - apps/*\n",
      );
      await writeFile(
        join(workspace, "apps/web/package.json"),
        JSON.stringify({ name: "web", dependencies: { next: "16.0.0" } }),
      );
    });

    afterAll(async () => {
      await rm(dir, { recursive: true, force: true });
      await rm(workspace, { recursive: true, force: true });
    });

    it.each([
      [["init", "--dry-run", "--yes"], 0, "success"],
      [["init", "--force", "--agent", "yes"], 3, "action_required"],
      [["init", "--cwd", "WORKSPACE", "--agent", "yes"], 3, "action_required"],
      [["add", "mfa", "--dry-run"], 0, "success"],
      [["add", "--preset", "saas", "--dry-run"], 0, "success"],
      [["add", "--adopt", "audit", "--snapshot", "SNAPSHOT"], 1, "error"],
      [["config", "--preset"], 0, "success"],
      [["blocks", "list", "--preset", "nope"], 2, "error"],
      [["blocks", "list"], 0, "success"],
      [["blocks", "view", "audit"], 0, "success"],
      [["blocks", "search", "audit"], 0, "success"],
      [["skills", "install", "--for", "cursor", "--dry-run"], 0, "success"],
      [["completion", "zsh"], 0, "success"],
      [["gen", "--snapshot", "SNAPSHOT", "--dry-run"], 0, "success"],
      [["spec", "validate"], 1, "error"],
      [["scaffold", "api", "--dry-run"], 1, "error"],
      [["dev", "keys", "--dry-run"], 0, "success"],
      [["doctor", "--snapshot", "SNAPSHOT"], 1, "error"],
      [["config"], 0, "success"],
      [["add", "mfa", "--dry-run"], 0, "success"],
      [["codemod", "0.9", "--dry-run"], 0, "success"],
    ])("describe the result of %j", async (argv, code, status) => {
      const result = await run(
        [
          ...argv.map(
            (word) =>
              ({ SNAPSHOT: snapshot, WORKSPACE: workspace })[word] ?? word,
          ),
          ...(argv.includes("--cwd") ? [] : ["--cwd", dir]),
          "--json",
        ],
        { cwd: dir },
      );

      const envelope = JSON.parse(result.stdout) as { status: string };

      expect([result.code, envelope.status]).toEqual([code, status]);
      expect(await errorsFor("cli-result-v1.json", envelope)).toEqual([]);
    });
  });

  it("list every CLI error code in the result schema", async () => {
    const schema = (await load("cli-result-v1.json")) as {
      $defs: { problem: { properties: { code: { enum: string[] } } } };
    };

    expect(schema.$defs.problem.properties.code.enum).toEqual(CLI_ERROR_CODES);
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
      database: {
        source: { snapshot: "supabase/snapshot.json" },
        schemas: ["public"],
      },
      gen: {
        casing: "camel",
        output: "src/lib/supabase/generated.ts",
        postgrestVersion: "13",
        tables: { audit_logs: { serviceRole: true } },
      },
      tooling: {
        doctor: { ignore: ["BS204"], strict: true, sources: ["app/**/*.tsx"] },
      },
      api: {
        specs: {
          entry: "src/lib/api.ts",
          outputs: [
            { format: "openapi", version: "3.2", ui: "scalar" },
            {
              format: "asyncapi",
              output: "asyncapi.yaml",
              overlays: ["o.yaml"],
            },
          ],
          failOn: "warning",
        },
      },
    };

    expect(await errorsFor("config-v1.json", config)).toEqual([]);
    expect(
      await errorsFor("config-v1.json", {
        ...config,
        gen: { ...config.gen, casing: "kebab" },
      }),
    ).toHaveLength(1);
  });

  it("describe the CLI keys and the environment blocks", async () => {
    const config = {
      gen: { tasks: ["types", "sql", "spec"], watchInterval: 1000 },
      tooling: {
        env: { output: ".env.development.local", prefix: "NEXT_PUBLIC_" },
        doctor: { only: ["BS100"], format: "sarif", output: "doctor.sarif" },
        scaffold: {
          api: { framework: "hono", tables: ["notes"], basePath: "/v1" },
        },
        skills: { agents: ["cursor"] },
        keys: { output: "supabase/keys.json" },
      },
      adapters: ["next", "client"],
      api: { specs: { manifest: "spec-manifest.json" } },
      $env: { staging: { tooling: { doctor: { strict: true } } } },
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
