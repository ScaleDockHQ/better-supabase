import { describe, expect, it } from "vitest";

import {
  cliContext,
  defineCliCommand,
  joinRepeated,
  list,
  parseCommandArgs,
} from "../../src/cli/command.ts";
import { resolveConfig } from "../../src/config/index.ts";

describe("list", () => {
  it("splits, trims and drops empty parts", () => {
    expect(list(" a, b,,c ")).toEqual(["a", "b", "c"]);
    expect(list(undefined)).toEqual([]);
  });
});

describe("joinRepeated", () => {
  it("joins repeated list options and leaves everything else alone", () => {
    expect(
      joinRepeated(
        ["--only", "BS100", "x", "--only=BS200,BS300", "--out", "r.json"],
        ["only"],
      ),
    ).toEqual(["--only=BS100,BS200,BS300", "x", "--out", "r.json"]);
  });

  it("stops at -- and skips a list option without a value", () => {
    expect(
      joinRepeated(["--only", "--strict", "--", "--only", "a"], ["only"]),
    ).toEqual(["--strict", "--", "--only", "a"]);
    expect(joinRepeated(["--only", "a"], [])).toEqual(["--only", "a"]);
  });
});

describe("defineCliCommand", () => {
  const command = defineCliCommand({
    meta: { name: "probe" },
    args: {
      only: { type: "string" },
      check: { type: "boolean" },
    },
    lists: ["only"],
    run: () => Promise.resolve({ code: 0 }),
  });

  it("parses repeated list options and the global ones", () => {
    const args = parseCommandArgs(command, [
      "--only",
      "a",
      "--only",
      "b",
      "--check",
      "--cwd",
      "app",
    ]);
    expect(list(String(args["only"]))).toEqual(["a", "b"]);
    expect(args["check"]).toBe(true);
    expect(args["cwd"]).toBe("app");
  });

  it("rejects a run without the context run() passes", () => {
    expect(() => cliContext(undefined)).toThrow(/run\(\)/);
    const context = {
      cwd: "/",
      config: resolveConfig({}, "/"),
      io: { stdout: () => {}, stderr: () => {} },
      env: {},
      json: false,
      signal: undefined,
    };
    expect(cliContext(context)).toBe(context);
  });

  it("needs static args to parse", () => {
    expect(() => parseCommandArgs({ args: () => ({}) }, ["--check"])).toThrow(
      /static args/,
    );
  });
});
