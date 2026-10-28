import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";
import type { BetterSupabaseConfig } from "../../../src/config/index.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { DEPENDENCY_RULES } from "../../../src/cli/doctor/dependencies.ts";
import { runRules } from "../../../src/cli/doctor/rules.ts";
import { VERSION } from "../../../src/cli/version.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { moduleLayout, renderBlocks } from "../../../src/sql/index.ts";
import { snapshotFixture } from "../fixtures/library.ts";

const base = await parseSnapshot(snapshotFixture);

const BS607 = DEPENDENCY_RULES.filter((rule) => rule.code === "BS607");

describe("BS607", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-bs607-"));
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  async function write(path: string, contents: string): Promise<void> {
    await mkdir(dirname(join(root, path)), { recursive: true });
    await writeFile(join(root, path), contents);
  }

  const context = (
    config: BetterSupabaseConfig = {},
    extra: Partial<DoctorContext> = {},
  ): DoctorContext => ({
    config: resolveConfig(config, root),
    snapshot: base,
    configToml: undefined,
    envFiles: [],
    gitignore: "",
    sources: [],
    ...extra,
  });

  it("reports node_modules off the lockfile", async () => {
    const findings = await runRules(
      context(
        {},
        {
          install: {
            installed: "0.34.0",
            lock: {
              path: "pnpm-lock.yaml",
              install: "pnpm install",
              versions: ["0.35.0"],
            },
          },
        },
      ),
      BS607,
    );

    expect(findings).toEqual([
      expect.objectContaining({
        code: "BS607",
        severity: "warning",
        target: "pnpm-lock.yaml",
        message: expect.stringContaining(
          "node_modules has better-supabase@0.34.0, but pnpm-lock.yaml locks 0.35.0.",
        ),
      }),
    ]);
    expect(findings[0]?.message).toContain("Run `pnpm install`.");
  });

  it("stays quiet when the lockfile names the installed version or links it", async () => {
    for (const versions of [["0.34.0", "0.35.0"], []]) {
      expect(
        await runRules(
          context(
            {},
            {
              install: {
                installed: "0.35.0",
                lock: {
                  path: "pnpm-lock.yaml",
                  install: "pnpm install",
                  versions,
                },
              },
            },
          ),
          BS607,
        ),
      ).toEqual([]);
    }
  });

  it("reports a block file newer than this release ships", async () => {
    const ctx = context({ blocks: ["memberships"] });
    const files = renderBlocks(["memberships"], moduleLayout(ctx.config));

    for (const file of files) {
      await write(file.path, file.contents);
    }

    expect(await runRules(ctx, BS607)).toEqual([]);

    const schema = files.find(
      (file) => file.module === "memberships" && file.kind === "schema",
    )!;

    await write(
      schema.path,
      schema.contents.replace(
        /^-- @bsb-block memberships@\d+/m,
        "-- @bsb-block memberships@99",
      ),
    );

    expect(await runRules(ctx, BS607)).toEqual([
      expect.objectContaining({
        target: schema.path,
        location: { file: schema.path, line: 1 },
        message: expect.stringContaining(
          `has memberships version 99; better-supabase@${VERSION} ships version`,
        ),
      }),
    ]);
  });

  it("reports better_supabase.blocks rows newer than this release ships", async () => {
    const live = (rows: Record<string, unknown>[] | Error): DoctorContext =>
      context(
        { blocks: ["memberships", "mfa"] },
        {
          database: {
            describe: "test",
            session: true,
            query: <R>() => {
              if (rows instanceof Error) {
                return Promise.reject(rows);
              }

              // SAFETY: the rows have the shape BS607 selects.
              return Promise.resolve(rows as R[]);
            },
          },
        },
      );

    expect(
      await runRules(
        live([
          { name: "memberships", block: null, version: 99 },
          { name: "mfa", block: null, version: 1 },
          { name: "audit", block: null, version: 99 },
        ]),
        BS607,
      ),
    ).toEqual([
      expect.objectContaining({
        target: "better_supabase.blocks.memberships",
        message: expect.stringContaining(
          "The database has memberships version 99;",
        ),
      }),
    ]);
    expect(await runRules(live(new Error("no table")), BS607)).toEqual([]);
  });
});
