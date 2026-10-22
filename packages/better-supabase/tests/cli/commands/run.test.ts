import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { InheritedOptions } from "../../../src/cli/exec.ts";

import { runCommand, runWithStackEnv } from "../../../src/cli/commands/run.ts";
import { parseCommandArgs } from "../../../src/cli/core/command.ts";
import { createLog } from "../../../src/cli/core/log.ts";
import { run } from "../../../src/cli/core/run.ts";
import { PROCESS_ENV } from "../../../src/cli/env.ts";
import { spawnInherited } from "../../../src/cli/exec.ts";
import { resolveConfig } from "../../../src/config/index.ts";

const STATUS = {
  API_URL: "http://127.0.0.1:55021",
  PUBLISHABLE_KEY: "sb_publishable_stack",
  SECRET_KEY: "sb_secret_stack",
};

let root: string;

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), "better-supabase-run-"));
  await writeFile(join(root, "package.json"), JSON.stringify({ name: "app" }));
  await writeFile(join(root, "status.json"), JSON.stringify(STATUS));
});

afterEach(async () => {
  await rm(root, { recursive: true, force: true });
});

describe("run", () => {
  const lines: string[] = [];

  const log = createLog({
    write: (line) => lines.push(line),
    paint: (_color, text) => text,
    debug: false,
  });

  const invoke = async (
    argv: string[],
    shell: Record<string, string>,
  ): Promise<{
    code: number;
    calls: [string, readonly string[], InheritedOptions][];
  }> => {
    lines.length = 0;
    const calls: [string, readonly string[], InheritedOptions][] = [];

    const result = await runWithStackEnv(
      resolveConfig({}, root),
      parseCommandArgs(runCommand, argv),
      {
        cwd: root,
        env: { [PROCESS_ENV]: shell },
        log,
        spawn: async (command, args, options) => {
          calls.push([command, args, options]);

          return 7;
        },
      },
    );

    return { code: result.code, calls };
  };

  it("passes the words after -- untouched and returns the command's exit code", async () => {
    const { code, calls } = await invoke(
      ["--status-file", "status.json", "--", "next", "dev", "--port", "3001"],
      {},
    );

    expect(code).toBe(7);
    expect(calls).toHaveLength(1);
    expect(calls[0]?.[0]).toBe("next");
    expect(calls[0]?.[1]).toEqual(["dev", "--port", "3001"]);
  });

  it("lets the stack override the shell and keeps the shell's other variables", async () => {
    const { calls } = await invoke(
      ["--status-file", "status.json", "--prefix", "next", "--", "next", "dev"],
      { SUPABASE_URL: "http://127.0.0.1:54321", PATH: "/bin", OTHER: "1" },
    );

    expect(calls[0]?.[2].env).toMatchObject({
      PATH: "/bin",
      OTHER: "1",
      SUPABASE_URL: "http://127.0.0.1:55021",
      NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:55021",
      SUPABASE_JWKS_URL: "http://127.0.0.1:55021/auth/v1/.well-known/jwks.json",
    });
  });

  it("warns about each stale exported variable without printing secrets", async () => {
    await invoke(["--status-file", "status.json", "--", "next", "dev"], {
      SUPABASE_URL: "http://127.0.0.1:54321",
      SUPABASE_SECRET_KEY: "sb_secret_old",
    });

    const output = lines.join("");

    expect(output).toContain(
      "SUPABASE_URL is exported as 127.0.0.1:54321, but the running stack has 127.0.0.1:55021.",
    );
    expect(output).toContain("SUPABASE_SECRET_KEY is exported as sha256:");
    expect(output).not.toContain("sb_secret_old");
    expect(output).not.toContain("sb_secret_stack");
  });

  it("needs a command after --", async () => {
    await expect(invoke(["--status-file", "status.json"], {})).rejects.toThrow(
      /Name the command to run after --/,
    );
  });

  it("runs a real command through the CLI with the stack env", async () => {
    const result = await run(
      [
        "dev",
        "run",
        "--status-file",
        "status.json",
        "--cwd",
        root,
        "--",
        process.execPath,
        "-e",
        "process.exit(process.env.SUPABASE_URL === 'http://127.0.0.1:55021' ? 3 : 1)",
      ],
      {
        env: { SUPABASE_URL: "http://127.0.0.1:54321" },
        io: { stdout: () => {}, stderr: () => {} },
      },
    );

    expect(result.code).toBe(3);
  });
});

describe("spawnInherited", () => {
  it("returns 127 for a command that does not exist", async () => {
    expect(
      await spawnInherited("better-supabase-no-such-command", [], {
        cwd: root,
        env: {},
      }),
    ).toBe(127);
  });
});
