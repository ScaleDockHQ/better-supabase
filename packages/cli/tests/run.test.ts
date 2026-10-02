import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type { CliIo } from "../src/io.ts";

import { defineCliCommand } from "../src/command.ts";
import { registerCommand, run } from "../src/run.ts";
import { VERSION } from "../src/version.ts";
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
      /^Unknown command "nope"\.\n\n.*\(better-supabase v/,
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
    expect((await run(["sql", "--help"])).stdout).toContain(
      "USAGE better-supabase sql [OPTIONS] [ACTION]",
    );
    expect((await run(["help", "sql"])).stdout).toContain(
      "USAGE better-supabase sql",
    );
  });

  it("runs a registered citty command with the context and its parsed args", async () => {
    registerCommand(
      "greet",
      defineCliCommand({
        meta: { name: "greet", description: "Says hello" },
        args: {
          name: { type: "string", required: true },
          loud: { type: "boolean" },
        },
        run: (args, { config }) =>
          Promise.resolve({
            code: 0,
            output: `${args.loud === true ? "HELLO" : "hello"} ${args.name} in ${config.root}`,
          }),
      }),
    );
    expect(
      await run(["greet", "--name", "ada", "--loud", "--cwd", dir]),
    ).toEqual({ code: 0, stdout: `HELLO ada in ${dir}\n`, stderr: "" });
    expect((await run(["help"])).stdout).toMatch(/greet +Says hello/);

    const missing = await run(["greet", "--cwd", dir]);
    expect(missing.code).toBe(2);
    expect(missing.stderr).toMatch(
      /^Missing required argument: --name\n\n.*USAGE better-supabase greet/s,
    );
  });

  it("adapts the deprecated (context) => result commands", async () => {
    // oxlint-disable-next-line typescript/no-deprecated -- tests the deprecated overload.
    registerCommand(
      "legacy",
      ({ args, cwd }) =>
        Promise.resolve({
          code: 0,
          output: JSON.stringify({ rest: args.rest, flags: args.flags, cwd }),
        }),
      "Usage: better-supabase legacy",
    );
    const result = await run([
      "legacy",
      "one",
      "--only",
      "a,b",
      "--check",
      "--out",
      "x.json",
      "--cwd",
      dir,
    ]);
    expect(JSON.parse(result.stdout)).toEqual({
      rest: ["one"],
      flags: { only: ["a", "b"], check: true, out: "x.json", cwd: dir },
      cwd: dir,
    });
    expect((await run(["legacy", "--help"])).stdout).toContain(
      "Usage: better-supabase legacy",
    );
  });

  it("finds the command after global options and reports bad actions and values", async () => {
    expect(
      (await run(["--cwd", dir, "--config=x.ts", "--help"])).stdout,
    ).toContain("USAGE better-supabase [OPTIONS]");
    expect((await run(["--", "gen"])).code).toBe(2);
    expect((await run(["--cwd", dir, "openapi"])).stderr).toBe(
      "Name an action. Run `better-supabase openapi emit`.\n",
    );
    expect((await run(["openapi", "publish", "--cwd", dir])).stderr).toMatch(
      /^Unknown openapi action "publish"/,
    );
    expect((await run(["skills", "--cwd", dir])).stderr).toMatch(
      /^Name an action\. Use `skills list`/,
    );
    expect((await run(["skills", "remove", "--cwd", dir])).stderr).toMatch(
      /^Unknown skills action "remove"/,
    );
    expect(
      await run(["init", "--casing", "pascal", "--cwd", dir]),
    ).toMatchObject({
      code: 2,
      stderr: '--casing must be "camel" or "snake"\n',
    });
    expect(
      await run(["introspect", "--format", "xml", "--cwd", dir]),
    ).toMatchObject({
      code: 2,
      stderr: '--format must be "snapshot" or "generator-metadata"\n',
    });
  });

  it("exits 0 for a command that returns no result", async () => {
    registerCommand(
      "quiet",
      defineCliCommand({
        meta: { name: "quiet" },
        args: {},
        // SAFETY: a third-party command may resolve to nothing.
        run: () => Promise.resolve(undefined as unknown as { code: number }),
      }),
    );
    expect(await run(["quiet", "--cwd", dir])).toEqual({
      code: 0,
      stdout: "",
      stderr: "",
    });
  });

  it("parses legacy flags with =, -h and --", async () => {
    // oxlint-disable-next-line typescript/no-deprecated -- tests the deprecated overload.
    registerCommand("legacy-flags", ({ args }) =>
      Promise.resolve({ code: 0, output: JSON.stringify(args) }),
    );
    const result = await run([
      "legacy-flags",
      "--out=a.json",
      "--only",
      "x",
      "--only=y",
      "-h2",
      "--",
      "--raw",
    ]);
    expect(JSON.parse(result.stdout)).toEqual({
      command: "legacy-flags",
      rest: ["-h2", "--raw"],
      flags: { out: "a.json", only: ["x", "y"] },
    });
  });

  it("prints the version", async () => {
    expect((await run(["version"])).stdout).toBe(`${VERSION}\n`);
  });

  it("turns a thrown error into exit code 1 and writes through a custom io", async () => {
    // oxlint-disable-next-line typescript/no-deprecated -- tests the deprecated overload.
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
