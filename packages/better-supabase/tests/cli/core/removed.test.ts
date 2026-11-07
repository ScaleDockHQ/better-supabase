import { describe, expect, it } from "vitest";

import { CliError } from "../../../src/cli/core/errors.ts";
import { removedFlag } from "../../../src/cli/core/removed.ts";
import { run } from "../../../src/cli/core/run.ts";
import { commandLine, splitCommandLine } from "../../../src/cli/core/shell.ts";
import { errorDoc } from "../error-doc.ts";

describe("removedFlag", () => {
  it("names what replaces --confirm, with an exit code of 2", () => {
    expect(() => {
      removedFlag(["init"], ["--confirm", "abc"]);
    }).toThrow(
      expect.objectContaining({
        code: "flag_renamed",
        exitCode: 2,
        problem: expect.objectContaining({
          flag: "--confirm",
          suggestion: "--yes --effects-digest <digest>",
        }),
      }),
    );
    expect(() => {
      removedFlag(["init"], ["--confirm=abc"]);
    }).toThrow(CliError);
  });

  it("ignores the flag after --", () => {
    expect(() => {
      removedFlag(["init"], ["--", "--confirm"]);
    }).not.toThrow();
  });

  it("rejects --confirm through run() under --json", async () => {
    const result = await run(["gen", "--confirm", "abc", "--json"]);

    expect(result.code).toBe(2);
    expect(result.stdout).toBe("");
    expect(errorDoc(result)).toMatchObject({
      reason: "flag_renamed",
      userActionRequired: false,
    });
  });
});

describe("splitCommandLine", () => {
  it("undoes commandLine, including quotes and empty words", () => {
    const words = ["better-supabase", "add", "it's here", "", "a b", "--x=1"];

    expect(splitCommandLine(commandLine(words))).toEqual(words);
  });
});
