import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { openapiFormat } from "../../src/openapi/format.ts";
import { defineApi } from "../../src/spec/api.ts";
import { defineDocumentFormat } from "../../src/spec/format.ts";
import { serializeDocument } from "../../src/spec/serialize.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { deepFreeze } from "./helpers.ts";

const betterSupabase = defineSupabase(schema);
const options = {
  info: { title: "CRM", version: "1.0.0" },
  resources: { customers: true, notes: { operations: ["list", "get"] } },
} as const;

describe("defineApi", () => {
  it("builds the model once per options object", () => {
    const first = defineApi(betterSupabase, options);
    const second = defineApi(betterSupabase, options);
    expect(second.model).toBe(first.model);
    expect(first.diagnostics).toEqual([]);
    expect(first.model.operations.map((operation) => operation.id)).toEqual([
      "listCustomers",
      "getCustomers",
      "createCustomers",
      "updateCustomers",
      "deleteCustomers",
      "listNotes",
      "getNotes",
    ]);
  });

  it("renders 3.1 by default and every version on request", () => {
    const api = defineApi(betterSupabase, options);
    expect(api.openapi().document.openapi).toBe("3.1.2");
    expect(api.openapi().version).toBe("3.1");
    expect(api.openapi({ version: "3.0" }).document.openapi).toBe("3.0.4");
    expect(api.openapi({ version: "3.2" }).document.openapi).toBe("3.2.1");
    const preview = api.openapi({ version: "3.3-preview" });
    expect(preview.document.openapi).toBe("3.3.0");
    expect(preview.fileName).toBe("openapi.json");
    expect(preview.diagnostics).toContainEqual(
      expect.objectContaining({ code: "preview-version", severity: "warning" }),
    );
  });

  it("returns a fresh copy on every render", () => {
    const api = defineApi(betterSupabase, options);
    const first = api.openapi().document;
    const second = api.openapi().document;
    expect(second).not.toBe(first);
    expect(second).toEqual(first);
  });

  it("renders the same bytes every time", () => {
    const text = () =>
      serializeDocument(
        defineApi(betterSupabase, {
          ...options,
          info: { ...options.info },
        }).openapi({ version: "3.2" }).document,
      );
    expect(text()).toBe(text());
  });

  it("never changes the model while lowering", () => {
    const api = defineApi(betterSupabase, {
      ...options,
      webhooks: [
        { id: "a.b", payload: { type: "object" }, standardWebhooks: true },
      ],
      fragments: [{ info: { description: "From a fragment" } }],
    });
    deepFreeze(api.model);
    for (const version of ["3.0", "3.1", "3.2", "3.3-preview"] as const) {
      expect(() => api.openapi({ version })).not.toThrow();
    }
  });

  it("passes a typed copy to transform and keeps its return value", () => {
    const api = defineApi(betterSupabase, options);
    const result = api.render(openapiFormat, {
      version: "3.2",
      transform: (rendered) => {
        expect(rendered.format).toBe("openapi");
        if (rendered.version === "3.2") {
          return {
            ...rendered.document,
            info: { ...rendered.document.info, title: "Renamed" },
          };
        }
        return;
      },
    });
    expect(result.document.info.title).toBe("Renamed");
    expect(api.openapi({ version: "3.2" }).document.info.title).toBe("CRM");

    const inPlace = api.openapi({
      transform: (rendered) => {
        Object.assign(rendered.document, { "x-edited": true });
        return;
      },
    });
    expect(inPlace.document["x-edited"]).toBe(true);
  });

  it("applies overlays through the engine and keeps its diagnostics", () => {
    const api = defineApi(betterSupabase, {
      ...options,
      applyOverlays: (document, overlays) => ({
        document: { ...(document as object), "x-overlays": overlays.length },
        diagnostics: [
          { code: "overlay-noop", severity: "info", message: "nothing" },
        ],
      }),
    });
    const result = api.openapi({ overlays: [{}, {}] });
    expect(result.document["x-overlays"]).toBe(2);
    expect(result.diagnostics).toContainEqual(
      expect.objectContaining({ code: "overlay-noop" }),
    );
    expect(() =>
      defineApi(betterSupabase, options).openapi({ overlays: [{}] }),
    ).toThrow("overlays need applyOverlays");
    const own = api.openapi({
      overlays: [{}],
      applyOverlays: (document) => ({ document }),
    });
    expect(own.document["x-overlays"]).toBeUndefined();
  });

  it("runs the format's lint after transform", () => {
    const api = defineApi(betterSupabase, options);
    const result = api.openapi({
      transform: (rendered) => {
        Object.assign(rendered.document, {
          security: [{ missingScheme: [] }],
        });
      },
    });
    expect(result.diagnostics).toContainEqual(
      expect.objectContaining({
        code: "security-unresolved",
        pointer: "/security",
      }),
    );
  });

  it("renders any DocumentFormat and rejects unknown versions", () => {
    const counter = defineDocumentFormat({
      id: "count",
      versions: {
        "1": { pin: "1", status: "stable" },
        "2-preview": { pin: "x", status: "preview" },
      },
      defaultVersion: "1",
      lower: (model, version, ctx) => {
        if (version === "2-preview") {
          ctx.report({ code: "c", severity: "info", message: "m" });
        }
        return { operations: model.operations.length };
      },
      lint: () => [{ code: "c", severity: "info", message: "m" }],
      fileName: (version) => `count-${version}.json`,
    });
    const api = defineApi(betterSupabase, options);
    const result = api.render(counter);
    expect(result).toMatchObject({
      format: "count",
      version: "1",
      document: { operations: 7 },
      fileName: "count-1.json",
    });
    const preview = api.render(counter, { version: "2-preview" });
    expect(preview.diagnostics.map((diagnostic) => diagnostic.code)).toEqual([
      "preview-version",
      "c",
    ]);
    expect(() =>
      // @ts-expect-error -- not a version of the format
      api.render(counter, { version: "3" }),
    ).toThrow('has no version "3"');
  });
});

describe("defineDocumentFormat", () => {
  const base = {
    id: "x",
    lower: () => ({}),
    fileName: () => "x.json",
  };

  it("checks the default version", () => {
    expect(() =>
      defineDocumentFormat({
        ...base,
        versions: { "1": { pin: "1", status: "stable" } },
        // @ts-expect-error -- not a listed version
        defaultVersion: "2",
      }),
    ).toThrow("is not in versions");
    expect(() =>
      defineDocumentFormat({
        ...base,
        versions: { "1": { pin: "1", status: "preview" } },
        defaultVersion: "1",
      }),
    ).toThrow("cannot be the default");
    expect(
      defineDocumentFormat({
        ...base,
        versions: { "1": { pin: "1", status: "stable" } },
        defaultVersion: "1",
      }).apiVersion,
    ).toBe(1);
  });
});
