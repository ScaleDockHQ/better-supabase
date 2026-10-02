import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { CliIo } from "../src/io.ts";

import { registerCommand, run } from "../src/run.ts";
import { fakeFetch } from "./fixtures/fake-fetch.ts";

const ENV = { SUPABASE_ACCESS_TOKEN: "sbp_test" };

/** A Management API that answers every query with no rows. */
const emptyProject = () => fakeFetch(() => ({ body: [] }));

describe("run", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "better-supabase-run-"));
  });

  afterEach(async () => {
    vi.unstubAllGlobals();
    await rm(dir, { recursive: true, force: true });
  });

  const io = (overrides: Partial<CliIo> = {}): CliIo => ({
    stdout: () => {},
    stderr: () => {},
    env: ENV,
    ...overrides,
  });

  it("rejects unknown commands and config files that do not exist", async () => {
    const unknown = await run(["nope"]);
    expect(unknown.code).toBe(2);
    expect(unknown.stderr).toMatch(
      /^Unknown command "nope"\.\n\nbetter-supabase /,
    );

    const missing = await run([
      "sql",
      "list",
      "--config",
      "gone.json",
      "--cwd",
      dir,
    ]);
    expect(missing).toEqual({
      code: 2,
      stdout: "",
      stderr: `Config file not found: ${join(dir, "gone.json")}\n`,
    });
  });

  it("prints the usage to stderr without a command and to stdout for help", async () => {
    expect(await run([])).toMatchObject({ code: 2, stdout: "" });
    expect((await run(["help"])).code).toBe(0);
    expect((await run(["sql", "--help"])).stdout).toMatch(
      /^Usage: better-supabase sql/,
    );
  });

  it("turns a thrown error into exit code 1 and writes through a custom io", async () => {
    registerCommand("explode", () => Promise.reject(new Error("boom")));
    const lines: string[] = [];
    const result = await run(["explode", "--cwd", dir], {
      io: io({ stderr: (text) => lines.push(text) }),
    });
    expect(result).toEqual({ code: 1, stdout: "", stderr: "boom\n" });
    expect(lines).toEqual(["boom\n"]);
  });

  it("introspects a hosted project and checks the saved snapshot", async () => {
    const api = emptyProject();
    vi.stubGlobal("fetch", api.fetch);
    const introspect = (...argv: string[]) =>
      run(["introspect", "--project-ref", "abc", ...argv, "--cwd", dir], {
        io: io(),
      });

    expect((await introspect()).stdout).toBe(
      "Wrote supabase/snapshot.json (0 tables).\n",
    );
    expect(api.calls[0]!.url).toBe(
      "https://api.supabase.com/v1/projects/abc/database/query/read-only",
    );
    expect((await introspect()).stdout).toBe(
      "Unchanged supabase/snapshot.json (0 tables).\n",
    );
    expect(await introspect("--check")).toMatchObject({
      code: 0,
      stdout: "supabase/snapshot.json is up to date.\n",
    });

    const path = join(dir, "supabase/snapshot.json");
    await writeFile(path, `${await readFile(path, "utf8")} `);
    expect(await introspect("--check")).toMatchObject({
      code: 1,
      stderr:
        "supabase/snapshot.json is out of date. Run `better-supabase introspect`.\n",
    });
  });

  it("writes generator metadata restricted to the configured schemas", async () => {
    vi.stubGlobal("fetch", emptyProject().fetch);
    const result = await run(
      [
        "introspect",
        "--project-ref",
        "abc",
        "--format",
        "generator-metadata",
        "--out",
        "meta.json",
        "--cwd",
        dir,
      ],
      { io: io() },
    );
    expect(result.stdout).toBe("Wrote meta.json (0 tables).\n");
    const meta = JSON.parse(await readFile(join(dir, "meta.json"), "utf8")) as {
      schemas: unknown[];
    };
    expect(meta.schemas).toEqual([]);
  });

  it("watches: reports load errors, regenerates on change and stays quiet otherwise", async () => {
    let failing = true;
    let printed = false;
    const controller = new AbortController();
    const api = fakeFetch((call) => {
      if (printed && call.body?.includes("t_enums")) controller.abort();
      return failing ? { status: 500, text: "upstream down" } : { body: [] };
    });
    vi.stubGlobal("fetch", api.fetch);
    const stdout: string[] = [];
    const stderr: string[] = [];
    const result = await run(
      [
        "gen",
        "--watch",
        "--interval",
        "1",
        "--project-ref",
        "abc",
        "--cwd",
        dir,
      ],
      {
        signal: controller.signal,
        io: io({
          stdout: (text) => {
            stdout.push(text);
            printed = true;
          },
          stderr: (text) => {
            stderr.push(text);
            failing = false;
          },
        }),
      },
    );
    expect(result.code).toBe(0);
    expect(stderr).toHaveLength(1);
    expect(stderr[0]).toContain("500");
    expect(stdout).toEqual([
      "Generated 0 tables:\n  src/lib/supabase/database.types.ts\n  src/lib/supabase/generated.ts\n",
    ]);
    expect(
      api.calls.filter((call) => call.body?.includes("t_enums")).length,
    ).toBeGreaterThanOrEqual(2);
  });

  it("stops a watch while it sleeps", async () => {
    vi.stubGlobal("fetch", emptyProject().fetch);
    const controller = new AbortController();
    const started = Date.now();
    const result = await run(
      ["gen", "--watch", "--project-ref", "abc", "--cwd", dir],
      {
        signal: controller.signal,
        io: io({ stdout: () => setTimeout(() => controller.abort(), 0) }),
      },
    );
    expect(result.code).toBe(0);
    expect(Date.now() - started).toBeLessThan(2000);
  });
});
