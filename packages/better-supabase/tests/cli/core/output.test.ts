import { describe, expect, it } from "vitest";

import { CliError } from "../../../src/cli/core/errors.ts";
import {
  RESULT_SCHEMA_URL,
  errorDocument,
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

  it("lists the next steps on stderr, so stdout stays the answer", () => {
    const next = [
      { command: "better-supabase gen", when: "to regenerate the clients" },
      { command: "supabase db reset", when: "to apply the migration" },
    ];

    expect(renderResult({ code: 0, output: "Added.", next }, text)).toEqual({
      stdout: "Added.",
      stderr: [
        "Next steps:",
        "  better-supabase gen  to regenerate the clients",
        "  supabase db reset    to apply the migration",
      ].join("\n"),
    });
    expect(
      renderResult({ code: 1, error: "bad", next: next.slice(0, 1) }, text),
    ).toEqual({
      stderr: [
        "bad",
        "",
        "Next steps:",
        "  better-supabase gen  to regenerate the clients",
      ].join("\n"),
    });
    expect(renderResult({ code: 0, warnings: ["Stale file."] }, text)).toEqual({
      stderr: "! Stale file.",
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
      next: [
        {
          command: "better-supabase gen",
          argv: ["better-supabase", "gen"],
          when: "next",
        },
      ],
    });
    expect(rendered.stderr).toBe("Created 2 files.");
    expect(parse(renderResult({ code: 0 }, json).stdout)).toEqual({
      $schema: RESULT_SCHEMA_URL,
      status: "success",
    });
  });

  it("prints a failure as one error document on stderr and leaves stdout empty", () => {
    const rendered = renderResult(
      { code: 1, output: "context", error: "stale", data: { stale: ["a"] } },
      json,
    );

    expect(rendered.stdout).toBeUndefined();

    const lines = (rendered.stderr ?? "").split("\n");

    expect(lines[0]).toBe("context");
    expect(JSON.parse(lines.at(-1) ?? "")).toMatchObject({
      status: "error",
      reason: "failed",
      message: "stale",
      data: { stale: ["a"] },
      userActionRequired: false,
      retryable: false,
    });
  });

  it("keeps the data of a report on stdout and writes no error document", () => {
    const rendered = renderResult(
      { code: 1, error: "2 findings", errorCode: "findings", data: { n: 2 } },
      json,
    );

    expect(parse(rendered.stdout)).toEqual({
      $schema: RESULT_SCHEMA_URL,
      status: "error",
      data: { n: 2 },
    });
    expect(rendered.stderr).toBe("2 findings");
  });

  it.each([
    [2, "usage", "error", false],
    [130, "cancelled", "error", false],
  ] as const)(
    "reports exit code %i as %s",
    (code, reason, status, userActionRequired) => {
      expect(
        JSON.parse(renderResult({ code, error: "stopped" }, json).stderr ?? ""),
      ).toMatchObject({ status, reason, userActionRequired });
    },
  );

  it("marks a missing input as action required and a network failure as retryable", () => {
    const input = new CliError("input_required", "needs --name");
    const network = new CliError("network_error", "no response");

    expect(errorDocument(input)).toMatchObject({
      status: "action_required",
      userActionRequired: true,
      retryable: false,
    });
    expect(errorDocument(network)).toMatchObject({
      status: "error",
      userActionRequired: false,
      retryable: true,
    });
  });

  it("keeps the error code a command returns", () => {
    expect(
      JSON.parse(
        renderResult({ code: 1, error: "Gone", errorCode: "not_found" }, json)
          .stderr ?? "",
      ),
    ).toMatchObject({ reason: "not_found" });
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

  it("lists the next steps with exact commands", () => {
    const hinted = new CliError("input_required", "Name a block.", {
      next: [{ command: "better-supabase blocks list", when: "to see them" }],
    });

    expect(renderError(hinted, text).stderr).toContain(
      "Next steps:\n  better-supabase blocks list  to see them",
    );
  });

  it("prints one error document line on stderr and nothing on stdout under --json", () => {
    const rendered = renderError(error, { ...json, usage: "USAGE" });

    expect(rendered.stdout).toBeUndefined();
    expect(rendered.stderr).not.toContain("\n");
    expect(JSON.parse(rendered.stderr ?? "")).toEqual(errorDocument(error));
  });
});
