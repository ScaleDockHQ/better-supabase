import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { CliEntry } from "../../src/cli/builtin-commands.ts";

import { builtinCommands } from "../../src/cli/builtin-commands.ts";
import { defineCliCommand } from "../../src/cli/command.ts";
import { createCli } from "../../src/cli/run.ts";

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
    const commands = new Map<string, CliEntry>([
      ["ping", { load: () => Promise.resolve(ping), command: ping }],
    ]);

    const cli = createCli({ commands });
    expect(cli.commandNames()).toEqual(["ping"]);
    expect((await cli.run(["ping", "--cwd", dir])).stdout).toBe(
      `pong ${dir}\n`,
    );
    const unknown = await cli.run(["gen"]);
    expect(unknown.code).toBe(2);
    expect(unknown.stderr).toContain('Unknown command "gen"');
  });

  it("keeps registrations out of other instances", () => {
    const first = createCli({ commands: new Map() });
    const second = createCli({ commands: new Map() });
    first.register("ping", ping);
    expect(first.commandNames()).toEqual(["ping"]);
    expect(second.commandNames()).toEqual([]);
  });

  it("skips the value of a global option when it looks for the command", async () => {
    const cli = createCli({ commands: new Map() });
    cli.register("ping", ping);
    const result = await cli.run(["--cwd", dir, "ping"]);
    expect(result.stdout).toBe(`pong ${dir}\n`);
  });

  it("describes the lazily loaded commands only", () => {
    const cli = createCli({ commands: builtinCommands() });
    cli.register("ping", ping);
    expect(cli.commandDescriptions().has("ping")).toBe(false);
    expect(cli.commandDescriptions().get("gen")).toContain("typed client");
  });
});
