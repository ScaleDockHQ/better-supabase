import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

import {
  CLI_ERROR_CODES,
  CLI_ERRORS_URL,
  CliError,
  errorText,
  exitCodeOf,
  failedResult,
  parseNames,
  toCliError,
} from "../../../src/cli/core/errors.ts";

const ERRORS_PAGE = readFileSync(
  new URL(
    "../../../../../apps/docs/content/docs/cli/errors.mdx",
    import.meta.url,
  ),
  "utf-8",
);

describe("the errors page", () => {
  const sections = new Map(
    ERRORS_PAGE.split(/^## /m)
      .slice(1)
      .map((section) => {
        const [heading = "", ...body] = section.split("\n");

        return [heading.replaceAll("`", "").trim(), body.join("\n")] as const;
      }),
  );

  it("names each code's exit code in its section", () => {
    for (const code of CLI_ERROR_CODES.filter((name) => name !== "failed")) {
      expect(`${code}: ${sections.get(code) ?? ""}`).toMatch(
        new RegExp(`Exit\\s+code\\s+${exitCodeOf(code)}\\.`),
      );
    }
  });
});

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

describe("error helpers", () => {
  it("prints any thrown value and wraps it as a failed result", () => {
    expect(errorText(new Error("boom"))).toBe("boom");
    expect(errorText("plain")).toBe("plain");
    expect(failedResult(new Error("boom"))).toEqual({ code: 1, error: "boom" });
  });

  it("parseNames returns the names, or a message naming the unknown ones", () => {
    const isColor = (value: string): value is "red" | "blue" =>
      value === "red" || value === "blue";

    expect(parseNames(["red"], isColor, "color", ["red", "blue"])).toEqual([
      "red",
    ]);
    expect(parseNames(["red", "pink"], isColor, "color", ["red", "blue"])).toBe(
      'Unknown color "pink". Available: red, blue.',
    );
  });
});
