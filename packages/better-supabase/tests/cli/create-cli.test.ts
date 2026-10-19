import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { builtinCommands } from "../../src/cli/builtin-commands.ts";
import { defineCliCommand } from "../../src/cli/core/command.ts";
import { createCli } from "../../src/cli/core/run.ts";

const ping = defineCliCommand({
  meta: { name: "ping", description: "Answers pong" },
  args: {},
  run: (_args, { cwd }) => Promise.resolve({ code: 0, output: `pong ${cwd}` }),
});

describe("createCli", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "bs-create-cli-"));
    await writeFile(join(dir, "package.json"), "{}");
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it("dispatches only the commands it was given", async () => {
    const cli = createCli({
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

  it("keeps registrations out of other instances", () => {
    const first = createCli({ commands: [], loaders: new Map() });
    const second = createCli({ commands: [], loaders: new Map() });
    first.register("ping", ping);
    expect(first.commandNames()).toEqual(["ping"]);
    expect(second.commandNames()).toEqual([]);
  });

  it("skips the value of a global option when it looks for the command", async () => {
    const cli = createCli({ commands: [], loaders: new Map() });
    cli.register("ping", ping);
    const result = await cli.run(["--cwd", dir, "ping"]);
    expect(result.stdout).toBe(`pong ${dir}\n`);
  });

  it("lists registered commands next to the built-in ones", async () => {
    const cli = createCli(builtinCommands());
    cli.register("ping", ping);
    expect(cli.commandNames()).toContain("ping");
    expect(await cli.help()).toMatch(/Other commands\n {2}ping +Answers pong/);
  });
});
