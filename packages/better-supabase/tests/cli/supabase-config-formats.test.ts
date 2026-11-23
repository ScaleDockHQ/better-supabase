import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { readSupabasePort } from "../../src/cli/config.ts";
import { enablePgDelta } from "../../src/cli/enable-pgdelta.ts";
import {
  configFileConflict,
  configFileIn,
  declarativeSchemasDir,
  detectWorkflow,
  findSupabaseRoot,
  httpHooks,
  pgFunctionHooks,
  readConfigInDir,
  readSupabaseConfig,
  schemaPaths,
  supabaseConfigFromText,
  tomlGet,
  tomlNumber,
  withConfigValue,
} from "../../src/cli/supabase-config.ts";

const TOML = `# the project
project_id = "demo"

[api]
port = 54321

[auth.hook.send_email]
enabled = true
secrets = "env(HOOK_SECRET)"

[db]
major_version = 17
`;

const JSONC = `{
  // the project
  "project_id": "demo",
  "api": { "port": 54321 },
  "auth": {
    "hook": {
      "send_email": { "enabled": true, "secrets": "env(HOOK_SECRET)" },
    },
  },
  "db": { "major_version": 17 },
}
`;

describe("the project config in each format", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "better-supabase-formats-"));
    await mkdir(join(dir, "supabase"));
  });

  afterEach(async () => {
    vi.unstubAllEnvs();
    await rm(dir, { recursive: true, force: true });
  });

  it.each([
    ["config.toml", TOML, "toml"],
    ["config.jsonc", JSONC, "jsonc"],
    [
      "config.json",
      JSON.stringify({ api: { port: 54_321 }, db: { major_version: 17 } }),
      "json",
    ],
  ] as const)("reads %s", async (name, text, format) => {
    await writeFile(join(dir, "supabase", name), text);

    const config = await readSupabaseConfig(dir);

    expect(config?.format).toBe(format);
    expect(config?.path).toBe(`supabase/${name}`);
    expect(tomlGet(config!.document, ["api", "port"])).toBe(54_321);
    expect(findSupabaseRoot(dir)).toBe(dir);
    expect(await readSupabasePort(dir, "api")).toBe(54_321);
  });

  it("prefers config.json over config.jsonc over config.toml, like the CLI", async () => {
    await writeFile(join(dir, "supabase/config.toml"), TOML);
    expect(configFileIn(dir)?.name).toBe("config.toml");

    await writeFile(join(dir, "supabase/config.jsonc"), JSONC);
    expect(configFileIn(dir)?.name).toBe("config.jsonc");
    expect(configFileConflict(dir)).toBe(false);

    await writeFile(join(dir, "supabase/config.json"), "{}");
    expect(configFileIn(dir)?.name).toBe("config.json");
    expect(configFileConflict(dir)).toBe(true);
  });

  it("finds a project that only has config.jsonc and follows its workflow", async () => {
    await writeFile(
      join(dir, "supabase/config.jsonc"),
      '{ "experimental": { "pgdelta": { "enabled": false } } }',
    );

    const config = await readSupabaseConfig(dir);

    expect(detectWorkflow(dir, config)).toBe("migra");
  });

  it("reads a stack folder in any format", async () => {
    await mkdir(join(dir, "supabase/stacks/demo"), { recursive: true });
    await writeFile(
      join(dir, "supabase/stacks/demo/config.jsonc"),
      '{ "db": { "port": 55000 } } // demo',
    );

    const stack = await readConfigInDir(join(dir, "supabase/stacks/demo"));

    expect(tomlGet(stack!.document, ["db", "port"])).toBe(55_000);
    expect(
      await readConfigInDir(join(dir, "supabase/stacks/none")),
    ).toBeUndefined();
  });

  it("resolves env() values in config.jsonc through @supabase/config", async () => {
    await writeFile(
      join(dir, "supabase/config.jsonc"),
      '{ "auth": { "site_url": "env(BS_JSONC_SITE_URL)" } }',
    );
    vi.stubEnv("BS_JSONC_SITE_URL", "https://example.test");

    const config = await readSupabaseConfig(dir);

    expect(config?.parser).toBe("@supabase/config");
    expect(tomlGet(config!.document, ["auth", "site_url"])).toBe(
      "https://example.test",
    );
    expect(config?.raw(["auth", "site_url"])).toBe("env(BS_JSONC_SITE_URL)");
  });
});

describe("locate", () => {
  it("finds a key, a table header and an enclosing table in TOML", () => {
    const config = supabaseConfigFromText(TOML);

    expect(config.locate(["api", "port"])).toEqual({
      line: 5,
      column: 1,
      exact: true,
    });
    expect(config.locate(["auth", "hook", "send_email"])).toMatchObject({
      line: 7,
      exact: true,
    });
    expect(config.locate(["auth", "hook", "send_email", "uri"])).toMatchObject({
      line: 7,
      exact: false,
    });
    expect(config.locate(["storage", "buckets"])).toBeUndefined();
  });

  it("finds dotted keys and quoted table names in TOML", () => {
    const config = supabaseConfigFromText(
      '[storage.buckets."my.docs"]\npublic = true\n[db]\nseed.enabled = true\n',
    );

    expect(config.locate(["storage", "buckets", "my.docs"])?.line).toBe(1);
    expect(
      config.locate(["storage", "buckets", "my.docs", "public"])?.line,
    ).toBe(2);
    expect(config.locate(["db", "seed", "enabled"])?.line).toBe(4);
  });

  it("finds a key with line and column in config.jsonc", () => {
    const config = supabaseConfigFromText(JSONC, "supabase/config.jsonc");

    expect(config.locate(["api", "port"])).toEqual({
      line: 4,
      column: 12,
      exact: true,
    });
    expect(config.locate(["auth", "hook", "send_email", "uri"])).toMatchObject({
      line: 7,
      exact: false,
    });
  });

  it("keeps env() values as written in raw()", () => {
    const config = supabaseConfigFromText(JSONC, "supabase/config.jsonc");

    expect(config.raw(["auth", "hook", "send_email", "secrets"])).toBe(
      "env(HOOK_SECRET)",
    );
  });
});

describe("withConfigValue", () => {
  it("replaces a TOML value and keeps the comment and other keys", () => {
    const text = withConfigValue(
      supabaseConfigFromText(TOML),
      ["db", "major_version"],
      15,
    );

    expect(text).toContain("major_version = 15");
    expect(text).toContain("# the project");
    expect(text).toContain('secrets = "env(HOOK_SECRET)"');
  });

  it("adds a key to an existing TOML table before the next table", () => {
    const text = withConfigValue(
      supabaseConfigFromText(TOML),
      ["api", "enabled"],
      true,
    );

    expect(text).toContain("[api]\nport = 54321\nenabled = true\n\n[auth");
  });

  it("appends a missing TOML table", () => {
    const text = withConfigValue(
      supabaseConfigFromText("[api]\nport = 1\n"),
      ["experimental", "pgdelta", "enabled"],
      true,
    );

    expect(text).toBe(
      "[api]\nport = 1\n\n[experimental.pgdelta]\nenabled = true\n",
    );
  });

  it("keeps CRLF line endings in TOML", () => {
    const text = withConfigValue(
      supabaseConfigFromText("[api]\r\nport = 1\r\n"),
      ["api", "port"],
      2,
    );

    expect(text).toBe("[api]\r\nport = 2\r\n");
  });

  it("edits config.jsonc and keeps its comments", () => {
    const config = supabaseConfigFromText(JSONC, "supabase/config.jsonc");

    const text = withConfigValue(config, ["db", "major_version"], 15);

    expect(text).toContain("// the project");
    expect(
      supabaseConfigFromText(text, "supabase/config.jsonc").document,
    ).toMatchObject({ db: { major_version: 15 } });
  });

  it("adds a nested object to config.jsonc", () => {
    const text = withConfigValue(
      supabaseConfigFromText(JSONC, "supabase/config.jsonc"),
      ["experimental", "pgdelta", "enabled"],
      true,
    );

    expect(
      supabaseConfigFromText(text, "supabase/config.jsonc").document,
    ).toMatchObject({ experimental: { pgdelta: { enabled: true } } });
    expect(text).toContain("// the project");
  });
});

describe("enablePgDelta on each format", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "better-supabase-pgdelta-"));
    await mkdir(join(dir, "supabase"));
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it("writes config.jsonc and leaves no config.toml behind", async () => {
    const path = join(dir, "supabase/config.jsonc");
    await writeFile(path, '{\n  // keep\n  "api": { "port": 1 }\n}\n');

    const lines = await enablePgDelta(dir, false);
    const written = await readFile(path, "utf-8");

    expect(lines).toEqual(["Enabled pg-delta in supabase/config.jsonc"]);
    expect(written).toContain("// keep");
    expect(written).toContain('"pgdelta"');
    expect(configFileIn(dir)?.name).toBe("config.jsonc");
  });

  it("writes config.toml as before", async () => {
    const path = join(dir, "supabase/config.toml");
    await writeFile(path, "[api]\nport = 1\n");

    await enablePgDelta(dir, false);

    expect(await readFile(path, "utf-8")).toBe(
      "[api]\nport = 1\n\n[experimental.pgdelta]\nenabled = true\n",
    );
  });
});

describe("JSON config edges", () => {
  const json = supabaseConfigFromText(
    '{ "a": null, "n": [1, { "x": true }], "s": 1 }',
    "supabase/config.json",
  );

  it.each([
    [["a"], "null"],
    [["n"], [1, { x: true }]],
    [["s", "deep"], undefined],
  ])("raw(%j) is %j", (path, value) => {
    expect(json.raw(path)).toEqual(value);
  });

  it("reads a non-object file as an empty table", () => {
    expect(supabaseConfigFromText("[1]", "config.json").document).toEqual({});
  });

  it.each([
    ["", ["a"], undefined],
    ['{ "a": 1 }', ["b", "c"], undefined],
    ['{ "a": { "b": 1 } }', ["a", "z"], { line: 1, column: 3, exact: false }],
  ])("locates %j at %j", (text, path, location) => {
    expect(supabaseConfigFromText(text, "config.jsonc").locate(path)).toEqual(
      location,
    );
  });

  it("keeps CRLF line endings when it edits JSON", () => {
    const text = withConfigValue(
      supabaseConfigFromText('{\r\n  "a": 1\r\n}', "config.json"),
      ["b"],
      ["x"],
    );

    expect(text).toContain('\r\n  "b": [\r\n');
    expect(JSON.parse(text)).toEqual({ a: 1, b: ["x"] });
  });
});

describe("TOML edges", () => {
  it("locates nothing outside every table, and a key under an unnamed header", () => {
    const config = supabaseConfigFromText("[.]\na = 1\n");

    expect(config.locate(["a"])).toEqual({ line: 2, column: 1, exact: true });
    expect(config.locate(["x", "y"])).toBeUndefined();
  });

  it.each([
    ["", ["api", "port"], 1, "[api]\nport = 1\n"],
    ["a = 1", ["api", "tags"], ["x"], 'a = 1\n\n[api]\ntags = ["x"]\n'],
    ["[api]\nport = 1", ["api", "on"], false, "[api]\nport = 1\non = false"],
    ["[api]\nport = 1 # old", ["api", "port"], 2, "[api]\nport = 2 # old"],
  ])("writes into %j", (text, path, value, expected) => {
    expect(withConfigValue(supabaseConfigFromText(text), path, value)).toBe(
      expected,
    );
  });
});

describe("tomlNumber", () => {
  it.each([
    [7, 7],
    ["42", 42],
    [" ", undefined],
    ["many", undefined],
    [true, undefined],
  ])("reads %j as %j", (value, expected) => {
    expect(tomlNumber({ a: value }, ["a"])).toBe(expected);
  });
});

describe("auth hooks", () => {
  const document = {
    auth: {
      hook: {
        text: "x",
        list: [1],
        pg: { enabled: "true", uri: "pg-functions://postgres/public/hook" },
        bad_pg: { enabled: true, uri: "pg-functions://postgres/only" },
        off: { enabled: false, uri: "https://hooks.test/off" },
        http: { enabled: true, uri: " https://hooks.test/h ", secrets: 5 },
        ftp: { enabled: true, uri: "ftp://hooks.test" },
        broken: { enabled: true, uri: "http://" },
      },
    },
  };

  it("lists the enabled pg-functions hooks", () => {
    expect(pgFunctionHooks(document)).toEqual([
      {
        hook: "pg",
        uri: "pg-functions://postgres/public/hook",
        schema: "public",
        name: "hook",
      },
    ]);
  });

  it("lists the enabled HTTP hooks with a valid URL", () => {
    expect(httpHooks(document)).toEqual([
      {
        hook: "http",
        uri: new URL("https://hooks.test/h"),
        secrets: undefined,
      },
    ]);
  });

  it.each([{}, { auth: { hook: "x" } }, { auth: { hook: [1] } }])(
    "finds none in %j",
    (doc) => {
      expect([...pgFunctionHooks(doc), ...httpHooks(doc)]).toEqual([]);
    },
  );
});

describe("schema folders", () => {
  it.each([
    ["./custom/", "supabase/custom"],
    ["  ", "supabase/schemas"],
  ])("puts declarative_schema_path %j at %s", (path, dir) => {
    const toml = supabaseConfigFromText(
      `[experimental.pgdelta]\ndeclarative_schema_path = "${path}"\n`,
    );

    expect(declarativeSchemasDir(toml, "pg-delta")).toBe(dir);
  });

  it.each([
    ["pg-delta", undefined],
    ["migra", undefined],
    ["migra", supabaseConfigFromText("[db.migrations]\nschema_paths = [1]\n")],
    ["migra", supabaseConfigFromText('[db.migrations]\nschema_paths = "x"\n')],
  ] as const)(
    "finds no %s files in a project without schemas",
    async (workflow, toml) => {
      expect(await schemaPaths("/nonexistent-root", toml, workflow)).toEqual({
        files: [],
        unlisted: [],
        configured: false,
      });
    },
  );
});
