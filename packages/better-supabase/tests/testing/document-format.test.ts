import { describe, expect, it } from "vitest";

import type { DocumentFormat } from "../../src/spec/format.ts";
import type { ApiModel } from "../../src/spec/model.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { openapiFormat } from "../../src/openapi/format.ts";
import { defineApi } from "../../src/spec/api.ts";
import { defineDocumentFormat } from "../../src/spec/format.ts";
import { ConformanceError } from "../../src/testing/conformance.ts";
import { testDocumentFormat } from "../../src/testing/document-format.ts";
import { testDocumentFormat as fromIndex } from "../../src/testing/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

/** A tiny third-party format: one line per operation, as text. */
const operationList = defineDocumentFormat({
  id: "operation-list",
  versions: { "1": { pin: "1.0.0", status: "stable" } },
  defaultVersion: "1",
  lower: (model) =>
    model.operations
      .map((operation) => `${operation.method.toUpperCase()} ${operation.path}`)
      .join("\n"),
  fileName: () => "operations.txt",
});

async function failures(
  format: DocumentFormat,
  model?: ApiModel,
): Promise<string[]> {
  const error = await testDocumentFormat(format, model ? { model } : {}).then(
    () => undefined,
    (cause: unknown) => cause,
  );
  expect(error).toBeInstanceOf(ConformanceError);
  return (error as ConformanceError).report.checks
    .filter((check) => !check.ok)
    .map((check) => check.name);
}

describe("testDocumentFormat", () => {
  it("passes openapiFormat on the sample model, in every version", async () => {
    const report = await testDocumentFormat(openapiFormat);
    expect(report.subject).toBe('DocumentFormat "openapi"');
    expect(report.checks.every((check) => check.ok)).toBe(true);
    expect(report.checks.map((check) => check.name)).toContain(
      "finds no error in its own output",
    );
  });

  it("passes openapiFormat on a model built from tables", async () => {
    const { model } = defineApi(defineSupabase(schema), {
      info: { title: "CRM", version: "1.0.0" },
      resources: { customers: true, notes: { operations: ["list", "get"] } },
    });
    await expect(
      fromIndex(openapiFormat, { model, versions: ["3.0", "3.2"] }),
    ).resolves.toMatchObject({ subject: 'DocumentFormat "openapi"' });
  });

  it("passes a text format without lint", async () => {
    const report = await testDocumentFormat(operationList);
    expect(report.checks.map((check) => check.name)).not.toContain(
      "finds no error in its own output",
    );
  });

  it("rejects a version the format does not list", async () => {
    const error = await testDocumentFormat(openapiFormat, {
      // @ts-expect-error -- 4.0 is not an OpenAPI version the format lists
      versions: ["4.0"],
    }).catch((cause: unknown) => cause);
    expect(error).toBeInstanceOf(ConformanceError);
  });

  it("reports every broken rule of a broken format", async () => {
    let calls = 0;
    const broken: DocumentFormat = {
      apiVersion: 2 as 1,
      id: "broken",
      versions: {
        "1": { pin: "", status: "stable" },
        draft: { pin: "abc", status: "preview" },
      },
      defaultVersion: "draft",
      lower: (model, version, ctx) => {
        calls += 1;
        ctx.report({ code: "Bad Code", severity: "error", message: "" });
        Object.assign(model.info, { version: String(calls) });
        return { version, calls, at: new Date(0) };
      },
      lint: () => [{ code: "lint-error", severity: "error", message: "x" }],
      fileName: (version) => `out/${version}-${calls}.json`,
    };
    expect(await failures(broken)).toEqual([
      "targets API v1 with an id",
      "lists versions with a pin and a known status",
      "defaults to a listed version that is not a preview",
      "lowers every version without mutating the model",
      "renders the same document twice",
      "renders plain JSON or text",
      "reports diagnostics with a code, a severity and a message",
      "names a bare, stable file per version",
    ]);
  });

  it("fails a format whose lint rejects its own output", async () => {
    const strict = defineDocumentFormat({
      id: "strict",
      versions: { "1": { pin: "1.0.0", status: "stable" } },
      defaultVersion: "1",
      lower: () => ({ ok: true }),
      lint: () => [
        { code: "always-wrong", severity: "error", message: "Never valid" },
      ],
      fileName: () => "strict.json",
    });
    expect(await failures(strict)).toEqual([
      "finds no error in its own output",
    ]);
  });
});
