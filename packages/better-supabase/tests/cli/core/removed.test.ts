import { describe, expect, it } from "vitest";

import { CliError } from "../../../src/cli/core/errors.ts";
import { removedFlag } from "../../../src/cli/core/removed.ts";

const message = (path: readonly string[], rest: readonly string[]): string => {
  try {
    removedFlag(path, rest);
  } catch (error) {
    if (error instanceof CliError) {
      return `${error.code}: ${error.message}`;
    }

    throw error;
  }

  return "";
};

describe("removedFlag", () => {
  it.each([
    [["db", "seed"], "--apply", "--yes"],
    [["doctor"], "--fix", "--yes"],
    [["dev", "env"], "--write", "--out <file>"],
    [["gen"], "--emit", "--only <file>"],
    [["gen"], "--out-dir", "--out <dir>"],
  ])("names the replacement of %j %s", (path, flag, replacement) => {
    expect(message(path, [flag])).toContain("flag_renamed");
    expect(message(path, [`${flag}=x`])).toContain(replacement);
  });

  it("leaves other commands, other flags and passthrough arguments alone", () => {
    expect(message(["db", "query"], ["--apply"])).toBe("");
    expect(message(["doctor"], ["--fix-grants"])).toBe("");
    expect(message(["doctor"], ["--", "--fix"])).toBe("");
  });
});
