import { defineCommand } from "citty";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { CliCommand } from "../../src/cli/core/command.ts";

import { defineCliCommand } from "../../src/cli/core/command.ts";
import { CliError } from "../../src/cli/core/errors.ts";
import {
  cliFromTree,
  commandNames,
  createCli,
} from "../../src/cli/core/run.ts";

const ping = defineCliCommand({
  meta: { name: "ping", description: "Answers pong" },
  args: {},
  run: (_args, { cwd }) => Promise.resolve({ code: 0, output: `pong ${cwd}` }),
});

describe("createCli", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "bsb-create-cli-"));
    await writeFile(join(dir, "package.json"), "{}");
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it("marks commands from defineCliCommand with apiVersion 1", () => {
    expect(ping.apiVersion).toBe(1);
  });

  it("refuses a command for another API version", () => {
    expect(() =>
      defineCliCommand({
        // SAFETY: a JavaScript caller can pass any version; the check is what this test covers.
        apiVersion: 2 as 1,
        meta: { name: "ping" },
        args: {},
        run: () => Promise.resolve({ code: 0 }),
      }),
    ).toThrow(CliError);
  });

  it("dispatches only the commands its tree has", async () => {
    const cli = cliFromTree({
      commands: [{ name: "ping", description: "Answers pong" }],
      loaders: new Map([["ping", () => Promise.resolve(ping)]]),
    });

    expect(cli.commandNames()).toEqual(["ping"]);
    expect((await cli.run(["ping", "--cwd", dir])).stdout).toBe(
      `pong ${dir}\n`,
    );
    const unknown = await cli.run(["gen"]);
    expect(unknown.code).toBe(2);
    expect(unknown.stderr).toContain('Unknown command "gen"');
  });

  it("keeps added commands out of other instances", () => {
    const first = createCli({ commands: { ping } });
    expect(first.commandNames()).toContain("ping");
    expect(createCli().commandNames()).not.toContain("ping");
    expect(commandNames()).not.toContain("ping");
  });

  it("skips the value of a global option when it looks for the command", async () => {
    const cli = createCli({ commands: { ping } });
    const result = await cli.run(["--cwd", dir, "ping"]);
    expect(result.stdout).toBe(`pong ${dir}\n`);
  });

  it("lists added commands next to the built-in ones", async () => {
    const cli = createCli({ commands: { ping } });
    expect(cli.commandNames()).toContain("gen");
    expect(await cli.help()).toMatch(/Other commands\n {2}ping +Answers pong/);
  });

  it("refuses a built-in or reserved name", () => {
    expect(() => createCli({ commands: { gen: ping } })).toThrow(/taken/);
    expect(() => createCli({ commands: { login: ping } })).toThrow(/taken/);
  });

  it("refuses a citty command that skipped defineCliCommand", () => {
    const raw = defineCommand({ meta: { name: "raw" }, run: () => undefined });
    // SAFETY: the type rules this out; a JavaScript caller can still pass it.
    const commands = { raw } as unknown as Record<string, CliCommand>;
    expect(() => createCli({ commands })).toThrow(/defineCliCommand/);
  });
});
