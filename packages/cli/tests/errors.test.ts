import { describe, expect, it } from "vitest";

import { CLI_ERRORS_URL, CliError, toCliError } from "../src/errors.ts";

describe("CliError", () => {
  it("carries Problem Details whose type links to the code's docs heading", () => {
    const error = new CliError("unknown_command", 'Unknown command "genn".', {
      suggestion: "gen",
    });
    expect(error.exitCode).toBe(2);
    expect(error.problem).toEqual({
      type: `${CLI_ERRORS_URL}#unknown_command`,
      title: "Unknown command",
      detail: 'Unknown command "genn".',
      code: "unknown_command",
      exitCode: 2,
      suggestion: "gen",
    });
  });

  it("exits 1 for failures and keeps an explicit exit code and cause", () => {
    const cause = new Error("boom");
    expect(new CliError("internal", "boom").exitCode).toBe(1);
    const failed = new CliError("failed", "stale", { exitCode: 3, cause });
    expect(failed.problem.exitCode).toBe(3);
    expect(failed.cause).toBe(cause);
    expect(failed.problem).not.toHaveProperty("cause");
  });
});

describe("toCliError", () => {
  it("keeps CLI errors, turns citty errors into usage and the rest into internal", () => {
    const own = new CliError("missing_value", "needs a token");
    expect(toCliError(own)).toBe(own);

    const citty = Object.assign(new Error("Missing required argument"), {
      name: "CLIError",
    });
    expect(toCliError(citty).code).toBe("usage");

    expect(toCliError(new TypeError("nope"))).toMatchObject({
      code: "internal",
      message: "nope",
      exitCode: 1,
    });
    expect(toCliError("thrown string").message).toBe("thrown string");
  });
});
