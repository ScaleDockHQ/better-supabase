import { describe, expect, it } from "vitest";

import { CliError } from "../../../src/cli/core/errors.ts";
import {
  RESULT_SCHEMA_URL,
  renderError,
  renderResult,
} from "../../../src/cli/core/output.ts";
import { painter } from "../../../src/cli/style.ts";

const text = { json: false, paint: painter(false) };
const json = { json: true, paint: painter(false) };

const parse = (stdout: string | undefined): unknown => JSON.parse(stdout ?? "");

describe("renderResult", () => {
  it("writes the output to stdout and the error to stderr as text", () => {
    expect(
      renderResult({ code: 1, output: "done", error: "bad" }, text),
    ).toEqual({ stdout: "done", stderr: "bad" });
    expect(renderResult({ code: 0 }, text)).toEqual({});
  });

  it("lists the next steps after a success", () => {
    const next = [
      { command: "better-supabase gen", when: "to regenerate the clients" },
      { command: "supabase db reset", when: "to apply the migration" },
    ];

    expect(renderResult({ code: 0, output: "Added.", next }, text)).toEqual({
      stdout: [
        "Added.",
        "",
        "Next:",
        "  better-supabase gen  to regenerate the clients",
        "  supabase db reset    to apply the migration",
      ].join("\n"),
    });
    expect(renderResult({ code: 1, error: "bad", next }, text)).toEqual({
      stderr: "bad",
    });
  });

  it("prints one success envelope under --json", () => {
    const rendered = renderResult(
      {
        code: 0,
        output: "Created 2 files.",
        data: { written: 2 },
        next: [{ command: "better-supabase gen", when: "next" }],
      },
      json,
    );

    expect(parse(rendered.stdout)).toEqual({
      $schema: RESULT_SCHEMA_URL,
      status: "success",
      data: { written: 2 },
      next: [{ command: "better-supabase gen", when: "next" }],
    });
    expect(rendered.stderr).toBe("Created 2 files.");
    expect(parse(renderResult({ code: 0 }, json).stdout)).toEqual({
      $schema: RESULT_SCHEMA_URL,
      status: "success",
    });
  });

  it("adds Problem Details to a failure, next to its data", () => {
    const rendered = renderResult(
      { code: 1, output: "context", error: "stale", data: { stale: ["a"] } },
      json,
    );

    expect(parse(rendered.stdout)).toMatchObject({
      status: "error",
      data: { stale: ["a"] },
      error: { code: "failed", detail: "stale", exitCode: 1 },
    });
    expect(rendered.stderr).toBe("context");
  });

  it.each([
    [2, "usage", "error"],
    [3, "input_required", "action_required"],
    [130, "cancelled", "error"],
  ])("reports exit code %i as %s", (code, errorCode, status) => {
    expect(
      parse(renderResult({ code, error: "stopped" }, json).stdout),
    ).toMatchObject({ status, error: { code: errorCode, exitCode: code } });
  });

  it("keeps the error code a command returns", () => {
    expect(
      parse(
        renderResult(
          { code: 1, error: "Out of date", errorCode: "check_failed" },
          json,
        ).stdout,
      ),
    ).toMatchObject({ error: { code: "check_failed" } });
  });
});

describe("renderError", () => {
  const error = new CliError("usage", "Missing --only");

  it("adds the usage text in text mode", () => {
    expect(renderError(error, { ...text, usage: "USAGE" })).toEqual({
      stderr: "Missing --only\n\nUSAGE",
    });
    expect(renderError(error, text)).toEqual({ stderr: "Missing --only" });
  });

  it("prints only the error envelope on stdout under --json", () => {
    expect(
      parse(renderError(error, { ...json, usage: "USAGE" }).stdout),
    ).toEqual({
      $schema: RESULT_SCHEMA_URL,
      status: "error",
      error: error.problem,
    });
  });
});
