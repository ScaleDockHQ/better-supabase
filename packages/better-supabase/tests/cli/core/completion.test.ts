import { describe, expect, it } from "vitest";

import { BLOCK_CATEGORIES } from "../../../src/blocks/index.ts";
import { completionScript, SHELLS } from "../../../src/cli/core/completion.ts";
import { run } from "../../../src/cli/core/run.ts";
import { GEN_TASKS } from "../../../src/cli/names.ts";
import {
  PRESET_NAMES,
  PRESET_TENANT_NAMES,
} from "../../../src/preset/index.ts";

/** The values `__complete` offers for `words`, the last one being typed. */
async function values(...words: string[]): Promise<string[]> {
  const result = await run(["__complete", "--", ...words]);

  expect(result.code).toBe(0);
  expect(result.stderr).toBe("");

  return result.stdout
    .split("\n")
    .filter(Boolean)
    .map((line) => line.split("\t")[0] ?? "");
}

describe("__complete", () => {
  it("offers the commands, then the subcommands, from the manifest", async () => {
    const top = await values("");
    expect(top).toEqual(
      expect.arrayContaining([
        "init",
        "add",
        "remove",
        "upgrade",
        "gen",
        "dev",
      ]),
    );
    expect(top).not.toContain("__complete");
    expect(await values("s")).toEqual(["skills", "spec"]);
    expect(await values("dev", "")).toEqual(["env", "run", "keys", "stack"]);
    expect(await values("db", "")).toEqual([
      "query",
      "diff",
      "seed",
      "backfill",
      "prune-workflows",
    ]);
    expect(await values("codemod", "0.")).toEqual([
      "0.4",
      "0.5",
      "0.6",
      "0.9",
      "0.11",
      "0.15",
      "0.29",
      "0.32",
      "0.35",
      "0.37",
    ]);
  });

  it("describes each candidate after a tab", async () => {
    const result = await run(["__complete", "--", "ge"]);

    expect(result.stdout).toBe(
      "gen\tWrites the typed client from the database, then every other generated file the config sets up\n",
    );
  });

  it("offers the command's options and the global ones", async () => {
    const options = await values("gen", "--");

    expect(options).toEqual(
      expect.arrayContaining([
        "--only",
        "--out-dir",
        "--check",
        "--json",
        "--agent",
        "--help",
      ]),
    );
    expect(options).not.toContain("--version");
    expect(await values("--v")).toEqual(["--version"]);
  });

  it("offers values from enums, value hints and the command's hooks", async () => {
    expect(await values("gen", "--agent", "")).toEqual(["auto", "yes", "no"]);
    expect(await values("gen", "--only", "")).toEqual([...GEN_TASKS]);
    expect(await values("init", "--preset", "")).toEqual([...PRESET_NAMES]);
    expect(await values("completion", "")).toEqual(["bash", "zsh", "fish"]);
    expect(await values("skills", "install", "--for", "c")).toEqual([
      "cursor",
      "claude",
    ]);
  });

  it("offers the convention values for init and add, and block categories", async () => {
    for (const command of ["init", "add"]) {
      expect(await values(command, "--casing", "")).toEqual(["snake", "camel"]);
      expect(await values(command, "--scope", "")).toEqual([
        "tenant",
        "user",
        "none",
      ]);
      expect(await values(command, "--tenant-name", "")).toEqual([
        ...PRESET_TENANT_NAMES,
      ]);
      expect(await values(command, "--access", "r")).toEqual(["roles"]);
      expect(await values(command, "--id-type", "u")).toEqual(["uuid"]);
      expect(await values(command, "--api", "")).toEqual(["none", "api"]);
    }

    expect(await values("add", "--preset", "")).toEqual([...PRESET_NAMES]);
    expect(await values("add", "--only", "")).toEqual([
      "blocks",
      "conventions",
    ]);
    expect(await values("blocks", "list", "--category", "")).toEqual([
      ...BLOCK_CATEGORIES,
    ]);
  });

  it("completes the value after = and the next item of a list", async () => {
    expect(await values("gen", "--agent=y")).toEqual(["--agent=yes"]);

    const [first, second] = GEN_TASKS;
    const rest = await values("gen", "--only", `${first},`);

    expect(rest).toContain(`${first},${second}`);
    expect(rest).not.toContain(`${first},${first}`);
  });

  it("offers block names for every block positional, after other words too", async () => {
    const blocks = await values("add", "");

    expect(blocks.length).toBeGreaterThan(10);
    expect(await values("add", blocks[0] ?? "", "--dry-run", "")).toEqual(
      blocks,
    );
    expect(await values("blocks", "view", "")).toEqual(blocks);
    expect(await values("remove", "")).toEqual(blocks);
    expect(await values("add", "--adopt", "")).toEqual(blocks);
  });

  it("asks the shell for file names for free-form values", async () => {
    const result = await run(["__complete", "--", "gen", "--out-dir", ""]);

    expect(result.stdout).toBe(":files\n");
  });

  it("skips the value of a global option when it finds the command", async () => {
    expect(await values("--cwd", "apps/web", "dev", "")).toContain("env");
  });

  it("offers nothing after a command it does not know", async () => {
    expect(await values("nope", "")).toEqual([]);
    expect(await values("sql", "nope", "")).toEqual([]);
  });

  it("offers doctor's formats and rule codes", async () => {
    expect(await values("doctor", "--format", "")).toEqual([
      "text",
      "sarif",
      "github",
    ]);
    expect(await values("doctor", "--only", "BS100,BS10")).toContain(
      "BS100,BS103",
    );
  });
});

describe("completion", () => {
  it.each(SHELLS)("prints the %s script for both bins", async (shell) => {
    const result = await run(["completion", shell], {
      env: { BETTER_SUPABASE_AGENT: "no" },
    });

    expect(result.code).toBe(0);
    expect(result.stdout).toBe(completionScript(shell));
    expect(result.stdout).toContain("__complete");
    expect(result.stdout).toMatch(/better-supabase[\s\S]*bsb/);
  });

  it("rejects an unknown shell", async () => {
    const result = await run(["completion", "tcsh"]);

    expect(result.code).toBe(2);
    expect(result.stderr).toContain(
      'Unknown shell "tcsh". Use bash, zsh or fish.',
    );
  });

  it("keeps the scripts stable", () => {
    for (const shell of SHELLS) {
      expect(completionScript(shell)).toMatchSnapshot(shell);
    }
  });
});
