import { describe, expect, it } from "vitest";

import { CliError } from "../src/errors.ts";
import { renderError, renderResult } from "../src/output.ts";
import { painter } from "../src/style.ts";

const text = { json: false, paint: painter(false) };
const json = { json: true, paint: painter(false) };

describe("renderResult", () => {
  it("writes the output to stdout and the error to stderr as text", () => {
    expect(
      renderResult({ code: 1, output: "done", error: "bad" }, text),
    ).toEqual({ stdout: "done", stderr: "bad" });
    expect(renderResult({ code: 0 }, text)).toEqual({});
  });

  it("prints the data as the one stdout document under --json", () => {
    expect(
      renderResult(
        { code: 0, output: "Wrote 2 files.", data: { written: 2 } },
        json,
      ),
    ).toEqual({
      stdout: JSON.stringify({ written: 2 }, null, 2),
      stderr: "Wrote 2 files.",
    });
    expect(renderResult({ code: 0, output: "ok" }, json)).toEqual({
      stdout: JSON.stringify({ message: "ok" }, null, 2),
    });
  });

  it("prints Problem Details for a failure without data", () => {
    const rendered = renderResult(
      { code: 1, output: "context", error: "stale" },
      json,
    );
    expect(JSON.parse(rendered.stdout ?? "")).toMatchObject({
      code: "failed",
      detail: "stale",
      exitCode: 1,
    });
    expect(rendered.stderr).toBe("context");
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

  it("prints only the problem on stdout under --json", () => {
    expect(renderError(error, { ...json, usage: "USAGE" })).toEqual({
      stdout: JSON.stringify(error.problem, null, 2),
    });
  });
});
