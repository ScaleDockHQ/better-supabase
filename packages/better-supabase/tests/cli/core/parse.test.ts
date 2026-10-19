import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { defineCliCommand } from "../../../src/cli/core/command.ts";
import { commandTree, resolveCommand } from "../../../src/cli/core/parse.ts";
import { cliFromTree, run } from "../../../src/cli/core/run.ts";

const echo = defineCliCommand({
  meta: { name: "a", description: "Echoes its arguments" },
  args: {
    names: {
      type: "positional",
      required: false,
      variadic: true,
      description: "Names",
    },
    mode: { type: "enum", options: ["fast", "slow"], description: "Mode" },
    check: { type: "boolean", description: "Check" },
    out: { type: "string", description: "Output" },
  },
  run: (args) =>
    Promise.resolve({
      code: 0,
      output: JSON.stringify({
        names: args._,
        mode: args.mode,
        check: args.check,
        out: args.out,
      }),
    }),
});

const grouped = () =>
  cliFromTree({
    commands: [
      {
        name: "grp",
        description: "A group",
        effects: [],
        subcommands: [{ name: "a", description: "Echoes", effects: [] }],
      },
    ],
    loaders: new Map([["grp a", () => Promise.resolve(echo)]]),
  });

describe("resolveCommand", () => {
  const tree = commandTree(
    [
      {
        name: "grp",
        description: "",
        subcommands: [{ name: "a", description: "" }],
      },
    ],
    new Map([["grp a", () => Promise.resolve(echo)]]),
  );

  it("walks to the leaf past global options and keeps the rest", () => {
    const resolution = resolveCommand(tree, [
      "--cwd",
      "x",
      "grp",
      "--json",
      "a",
      "one",
    ]);

    expect(resolution).toMatchObject({
      kind: "command",
      node: { path: ["grp", "a"] },
      rest: ["--cwd", "x", "--json", "one"],
    });
  });

  it("reports the unknown name with its parent and the candidates", () => {
    expect(resolveCommand(tree, ["grp", "b"])).toMatchObject({
      kind: "unknown",
      parent: ["grp"],
      name: "b",
      candidates: ["a"],
    });
    expect(resolveCommand(tree, ["--", "grp"])).toMatchObject({
      kind: "root",
    });
  });
});

describe("strict parsing", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "bs-parse-"));
    await writeFile(join(dir, "package.json"), "{}");
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it("runs a subcommand with its parsed arguments", async () => {
    const result = await grouped().run([
      "grp",
      "a",
      "one",
      "two",
      "--mode",
      "fast",
      "--no-check",
      "--out",
      "-",
      "--cwd",
      dir,
    ]);

    expect(result.stderr).toBe("");
    expect(JSON.parse(result.stdout)).toEqual({
      names: ["one", "two"],
      mode: "fast",
      check: false,
      out: "-",
    });
  });

  it("shows a group's commands on stderr when no subcommand is named", async () => {
    const result = await grouped().run(["grp"]);
    expect(result.code).toBe(2);
    expect(result.stderr).toMatch(
      /^Name a grp subcommand: a\.\n\nUsage: better-supabase grp <command>/,
    );
    expect(result.stderr).toMatch(/Commands\n {2}a +Echoes/);
  });

  it("suggests the closest subcommand", async () => {
    const result = await grouped().run(["grp", "b"]);
    expect(result.code).toBe(2);
    expect(result.stderr).toMatch(
      /^Unknown command "grp b"\. Did you mean "grp a"\?/,
    );
  });

  it("rejects unknown options with a suggestion", async () => {
    const result = await run(["gen", "--chek", "--json", "--cwd", dir]);
    expect(result.code).toBe(2);
    expect(JSON.parse(result.stdout)).toMatchObject({
      error: {
        code: "usage",
        flag: "--chek",
        suggestion: "--check",
      },
    });
  });

  it("rejects values outside an enum", async () => {
    const result = await grouped().run([
      "grp",
      "a",
      "--mode=medium",
      "--cwd",
      dir,
    ]);

    expect(result.code).toBe(2);
    expect(result.stderr).toMatch(/^--mode takes fast, slow, not "medium"\./);
  });

  it("rejects arguments a command doesn't declare", async () => {
    const init = await run(["init", "foo", "--cwd", dir]);
    expect(init.code).toBe(2);
    expect(init.stderr).toMatch(
      /^better-supabase init takes no arguments, and got "foo"\./,
    );

    const gen = await run(["gen", "help", "--cwd", dir, "--json"]);
    expect(JSON.parse(gen.stdout)).toMatchObject({
      error: {
        code: "usage",
        suggestion: "better-supabase gen --help",
      },
    });
  });

  it("answers --version and version only at the root", async () => {
    expect((await run(["--version"])).code).toBe(0);
    expect((await run(["version"])).code).toBe(0);

    const nested = await run(["gen", "--version", "--cwd", dir]);
    expect(nested.code).toBe(2);
    expect(nested.stderr).toMatch(/^Unknown option --version/);
  });

  it("prints a command's help through help <command>, and rejects unknown topics", async () => {
    const gen = await run(["help", "gen"]);
    expect(gen.code).toBe(0);
    expect(gen.stdout).toMatch(/^Usage: better-supabase gen \[options\]/);

    const unknown = await run(["help", "gne"]);
    expect(unknown.code).toBe(2);
    expect(unknown.stderr).toMatch(
      /^Unknown command "gne"\. Did you mean "gen"\?/,
    );
  });

  it("uses the name the CLI was called with in help", async () => {
    const result = await run(["gen", "--help"], { bin: "bsb" });
    expect(result.stdout).toMatch(/^Usage: bsb gen \[options\]/);
    expect(result.stdout).toContain("$ bsb gen --check");
  });
});
