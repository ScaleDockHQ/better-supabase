import { existsSync, realpathSync } from "node:fs";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { schemaStampPath } from "../../src/cli/content-mapper.ts";
import {
  EMPTY_MODULE,
  loadProject,
  realPath,
} from "../../src/mapper/project.ts";
import { snapshotPath } from "../cli/fixtures/library.ts";

const snapshot = fileURLToPath(snapshotPath);

describe("loadProject", () => {
  let root: string;
  let tsconfig: string;

  beforeEach(async () => {
    root = realpathSync(
      await mkdtemp(join(tmpdir(), "better-supabase-mapper-")),
    );
    tsconfig = join(root, "tsconfig.json");
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  const configure = (source: string, casing = "camel") =>
    writeFile(
      join(root, "better-supabase.config.json"),
      JSON.stringify({
        database: { source: { snapshot: source } },
        gen: { casing, output: "src/generated.ts", contentMapper: true },
      }),
    );

  it("serves the types module and watches the config, the snapshot and the stamp", async () => {
    await configure(snapshot);
    const project = await loadProject(tsconfig, {}, {});

    expect(project.diagnostics).toEqual([]);
    expect(project.text).toContain("declare namespace SupabaseTypes {");
    expect(project.text).toContain("export type Models = {");
    expect(project.file).toBe(join(root, "src/schema.bsb"));
    expect(project.watchedFiles).toEqual([
      join(root, "better-supabase.config.json"),
      realpathSync(snapshot),
      join(root, "supabase/config.toml"),
      schemaStampPath(root, "src/generated.ts"),
    ]);
    expect(existsSync(schemaStampPath(root, "src/generated.ts"))).toBe(true);

    expect((await loadProject(tsconfig, {}, {})).configIdentity).toBe(
      project.configIdentity,
    );
    expect(
      (await loadProject(tsconfig, { config: "x" }, {})).configIdentity,
    ).not.toBe(project.configIdentity);

    await configure(snapshot, "snake");
    expect((await loadProject(tsconfig, {}, {})).configIdentity).not.toBe(
      project.configIdentity,
    );
  });

  it("reports the options it doesn't read", async () => {
    await configure(snapshot);

    expect(
      (await loadProject(tsconfig, { casing: "snake", config: 1 }, {}))
        .optionDiagnostics,
    ).toMatchObject([
      { path: ["casing"], code: 606 },
      { path: ["config"], code: 606 },
    ]);
  });

  it("serves the last types when the source fails, and nothing before a first render", async () => {
    await configure("missing.json");
    const first = await loadProject(tsconfig, {}, {});

    expect(first.text).toBe(EMPTY_MODULE);
    expect(first.diagnostics).toMatchObject([
      {
        code: 603,
        messageText: expect.stringContaining(
          "Snapshot not found: missing.json",
        ),
      },
    ]);

    await configure(snapshot);
    const served = await loadProject(tsconfig, {}, {});
    await configure("missing.json");
    const stale = await loadProject(tsconfig, {}, {});

    expect(stale.text).toBe(served.text);
    expect(stale.diagnostics).toMatchObject([{ code: 604 }]);
    expect(stale.configIdentity).not.toBe(served.configIdentity);
  });

  it("reports a missing or invalid config on the file", async () => {
    const missing = await loadProject(tsconfig, {}, {});

    expect(missing).toMatchObject({
      text: EMPTY_MODULE,
      watchedFiles: [],
      diagnostics: [{ code: 603 }],
    });
    expect(missing.diagnostics[0]?.messageText).toContain(
      "No better-supabase config found",
    );

    await writeFile(join(root, "better-supabase.config.json"), '{"gen": 1}');

    expect(await loadProject(tsconfig, {}, {})).toMatchObject({
      watchedFiles: [join(root, "better-supabase.config.json")],
      diagnostics: [{ code: 603 }],
    });
  });
});

describe("realPath", () => {
  it("keeps a missing file's name under its nearest real parent", () => {
    const tmp = realpathSync(tmpdir());

    expect(realPath(join(tmpdir(), "nope", "file.txt"))).toBe(
      join(tmp, "nope", "file.txt"),
    );
  });
});
