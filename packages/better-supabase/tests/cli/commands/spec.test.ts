import { existsSync } from "node:fs";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { uiPath } from "../../../src/cli/commands/spec.ts";
import { run } from "../../../src/cli/run.ts";
import { fails, formatDiagnostics } from "../../../src/cli/spec/diagnostics.ts";
import { defineSupabase } from "../../../src/core/define.ts";
import { defineApi } from "../../../src/spec/api.ts";
import { schema } from "../../fixtures/generated-camel.ts";

const api = defineApi(defineSupabase(schema), {
  info: { title: "CRM", version: "1.0.0" },
  resources: { customers: true, notes: { operations: ["list", "get"] } },
});

declare global {
  var specApiFixture: unknown;
}

let dir = "";

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "better-supabase-spec-"));
  globalThis.specApiFixture = api;
  await writeFile(
    join(dir, "api.mjs"),
    "export const api = globalThis.specApiFixture;\n",
  );
  await writeFile(join(dir, "package.json"), JSON.stringify({ name: "app" }));
});

afterEach(async () => {
  await rm(dir, { recursive: true, force: true });
});

const spec = (...args: string[]) =>
  run(["spec", ...args, "--entry", "api.mjs", "--cwd", dir]);

const readJson = async (path: string): Promise<Record<string, unknown>> =>
  // SAFETY: the test reads JSON files the command wrote.
  JSON.parse(await readFile(join(dir, path), "utf8")) as Record<
    string,
    unknown
  >;

describe("spec emit", () => {
  it("writes the default OpenAPI output, then reuses the cache", async () => {
    const first = await spec("emit");
    expect(first.code).toBe(0);
    expect(first.stdout).toContain("Wrote openapi.json (openapi 3.1)");
    expect(await readJson("openapi.json")).toMatchObject({ openapi: "3.1.2" });
    const second = await spec("emit");
    expect(second.stdout).toContain(
      "Unchanged openapi.json (openapi 3.1, cached)",
    );
    const manifest = await readJson(
      "node_modules/.cache/better-supabase/specs/diagnostics.json",
    );
    expect(manifest).toMatchObject({ version: 1, ok: true, failOn: "error" });
  });

  it("renders another version to its own file, as YAML, with a reference page", async () => {
    const result = await spec(
      "emit",
      "openapi",
      "--spec-version",
      "3.0",
      "--yaml",
      "--ui",
      "redoc",
    );
    expect(result.code).toBe(0);
    expect(result.stdout).toContain("Wrote openapi-3.0.yaml");
    const text = await readFile(join(dir, "openapi-3.0.yaml"), "utf8");
    expect(text).toMatch(/^openapi: 3\.0\.\d/m);
    const html = await readFile(join(dir, uiPath("openapi-3.0.yaml")), "utf8");
    expect(html).toContain("redoc");
    expect(html).toContain("./openapi-3.0.yaml");
  });

  it("writes to --out and a manifest file, without the cache", async () => {
    const result = await spec(
      "emit",
      "--out",
      "docs/api.json",
      "--manifest",
      "report.json",
      "--no-cache",
    );
    expect(result.code).toBe(0);
    expect(existsSync(join(dir, "docs/api.json"))).toBe(true);
    const manifest = await readJson("report.json");
    expect(manifest["outputs"]).toEqual([
      expect.objectContaining({
        path: "docs/api.json",
        status: "written",
        cached: false,
      }),
    ]);
  });

  it("fails on warnings with --fail-on warning", async () => {
    const preview = await spec(
      "emit",
      "openapi",
      "--spec-version",
      "3.3-preview",
    );
    expect(preview.code).toBe(0);
    expect(preview.stdout).toContain("preview-version");
    const strict = await spec(
      "emit",
      "openapi",
      "--spec-version",
      "3.3-preview",
      "--fail-on",
      "warning",
    );
    expect(strict.code).toBe(1);
    expect(strict.stderr).toContain("--fail-on warning");
  });

  it("returns the manifest under --json", async () => {
    const result = await spec("emit", "--json");
    expect(JSON.parse(result.stdout)).toMatchObject({
      $schema:
        "https://unpkg.com/better-supabase/schemas/spec-manifest-v1.json",
      outputs: [expect.objectContaining({ format: "openapi", version: "3.1" })],
    });
  });
});

describe("spec emit --watch", () => {
  it("emits again when the entry changes and when the config changes", async () => {
    const controller = new AbortController();
    const lines: string[] = [];
    await writeFile(
      join(dir, "better-supabase.config.mjs"),
      "export default { specs: { entry: 'api.mjs' } };\n",
    );
    const watching = run(
      ["spec", "emit", "--watch", "--interval", "20", "--cwd", dir],
      {
        signal: controller.signal,
        io: {
          stdout: (text) => {
            lines.push(text);
          },
          stderr: (text) => {
            lines.push(text);
          },
        },
      },
    );
    const waitFor = async (pattern: RegExp): Promise<void> => {
      for (let attempt = 0; attempt < 200; attempt += 1) {
        if (lines.some((line) => pattern.test(line))) return;
        await new Promise((done) => {
          setTimeout(done, 20);
        });
      }
      throw new Error(`no output matched ${pattern}: ${lines.join("")}`);
    };
    await waitFor(/Wrote openapi\.json/);
    await new Promise((done) => {
      setTimeout(done, 30);
    });
    await writeFile(join(dir, "api.mjs"), "export const api = undefined;\n");
    await waitFor(/must export `api`/);
    await writeFile(
      join(dir, "better-supabase.config.mjs"),
      "export default { specs: { entry: 'api.mjs', outputs: [{ format: 'openapi', output: 'next.json' }] } };\n",
    );
    await writeFile(
      join(dir, "api.mjs"),
      "export const api = globalThis.specApiFixture;\n",
    );
    await waitFor(/Wrote next\.json/);
    controller.abort();
    expect((await watching).code).toBe(0);
  });
});

describe("spec diagnostics", () => {
  it("fails by level and groups findings by severity", () => {
    const warning = { code: "w", severity: "warning", message: "m" } as const;
    expect(fails(warning, "error")).toBe(false);
    expect(fails(warning, "warning")).toBe(true);
    expect(fails({ ...warning, severity: "error" }, "never")).toBe(false);
    expect(() => fails(warning, "loud" as never)).toThrow(
      "Unknown fail-on level",
    );
    const text = formatDiagnostics([
      {
        format: "openapi",
        version: "3.1",
        pin: "3.1.2",
        path: "openapi.json",
        sha256: "",
        status: "validated",
        cached: false,
        diagnostics: [
          { ...warning, pointer: "/info" },
          { code: "i", severity: "info", message: "note" },
        ],
      },
    ]);
    expect(text).toBe(
      "Warnings (1):\n  openapi.json w at /info: m\nInfo (1):\n  openapi.json i: note",
    );
  });
});

describe("spec check", () => {
  it("passes when the file matches and fails when it drifts", async () => {
    await spec("emit");
    expect((await spec("check")).code).toBe(0);
    const json = await readFile(join(dir, "openapi.json"), "utf8");
    await writeFile(join(dir, "openapi.json"), json.replaceAll("\n", "\r\n"));
    expect((await spec("check")).code).toBe(0);
    await writeFile(join(dir, "openapi.json"), "{}\n");
    const stale = await spec("check");
    expect(stale.code).toBe(1);
    expect(stale.stdout).toContain("output-stale");
    expect(stale.stderr).toContain("out of date");
  });

  it("reports a missing file", async () => {
    const missing = await spec("check");
    expect(missing.code).toBe(1);
    expect(missing.stdout).toContain("output-missing");
  });
});

describe("spec validate", () => {
  it("checks every OpenAPI version against its official schema", async () => {
    for (const version of ["3.0", "3.1", "3.2"]) {
      const result = await spec(
        "validate",
        "openapi",
        "--spec-version",
        version,
      );
      expect(result.stderr).toBe("");
      expect(result.code).toBe(0);
      expect(result.stdout).toContain("Checked");
    }
    const preview = await spec(
      "validate",
      "openapi",
      "--spec-version",
      "3.3-preview",
    );
    expect(preview.stdout).toContain("schema-unavailable");
  });
});

describe("spec arguments", () => {
  it("rejects unknown actions, levels, UIs and versions", async () => {
    expect((await spec()).code).toBe(2);
    expect((await spec("publish")).code).toBe(2);
    expect((await spec("emit", "--fail-on", "loud")).code).toBe(2);
    expect((await spec("emit", "--ui", "nope")).code).toBe(2);
    expect((await spec("check", "--watch")).code).toBe(2);
    expect((await spec("emit", "--watch", "--interval", "0")).code).toBe(2);
    const version = await spec("emit", "openapi", "--spec-version", "9.9");
    expect(version.code).toBe(1);
    expect(version.stderr).toContain("no version");
    const format = await spec("emit", "graphql");
    expect(format.code).toBe(1);
    expect(format.stderr).toContain("Unknown document format");
  });

  it("explains an entry that exports nothing usable", async () => {
    await writeFile(join(dir, "empty.mjs"), "export const nothing = 1;\n");
    const result = await run([
      "spec",
      "emit",
      "--entry",
      "empty.mjs",
      "--cwd",
      dir,
    ]);
    expect(result.code).toBe(1);
    expect(result.stderr).toContain("must export `api`");
    const absent = await run([
      "spec",
      "emit",
      "--entry",
      "absent.mjs",
      "--cwd",
      dir,
    ]);
    expect(absent.stderr).toContain("Could not load");
  });

  it("emits a finished document export and flags another version", async () => {
    await writeFile(
      join(dir, "doc.mjs"),
      "export default { openapi: '3.1.0', info: { title: 'x', version: '1' }, paths: {} };\n",
    );
    const emit = await run([
      "spec",
      "emit",
      "--entry",
      "doc.mjs",
      "--cwd",
      dir,
    ]);
    expect(emit.stderr).toBe("");
    expect(emit.code).toBe(0);
    const other = await run([
      "spec",
      "emit",
      "openapi",
      "--spec-version",
      "3.2",
      "--entry",
      "doc.mjs",
      "--cwd",
      dir,
    ]);
    expect(other.code).toBe(1);
    expect(other.stdout).toContain("document-version");
  });
});
