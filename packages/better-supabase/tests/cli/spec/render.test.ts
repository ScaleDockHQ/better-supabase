import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { SpecEntry } from "../../../src/cli/spec/entry.ts";

import {
  documentFormatId,
  loadSpecEntry,
} from "../../../src/cli/spec/entry.ts";
import {
  formatRegistry,
  isDocumentFormat,
} from "../../../src/cli/spec/formats.ts";
import { renderTarget } from "../../../src/cli/spec/render.ts";
import { resolveTargets } from "../../../src/cli/spec/targets.ts";
import { defineSupabase } from "../../../src/core/define.ts";
import { openapiFormat } from "../../../src/openapi/format.ts";
import { defineApi } from "../../../src/spec/api.ts";
import { schema } from "../../fixtures/generated-camel.ts";

const api = defineApi(defineSupabase(schema), {
  info: { title: "CRM", version: "1.0.0" },
  resources: { customers: true },
});

let root = "";

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), "better-supabase-render-"));
});

afterEach(async () => {
  await rm(root, { recursive: true, force: true });
});

const target = (overlays: string[] = []) =>
  resolveTargets([{ format: "openapi", overlays }], formatRegistry(), {})[0] ??
  (() => {
    throw new Error("no target");
  })();

const entry: SpecEntry = { api, documents: new Map(), formats: [] };

describe("renderTarget", () => {
  it("applies JSON and YAML overlays", async () => {
    await writeFile(
      join(root, "title.yaml"),
      "overlay: 1.1.0\ninfo: { title: t, version: '1' }\nactions:\n  - target: $.info\n    update: { title: Renamed }\n",
    );
    await writeFile(
      join(root, "summary.json"),
      JSON.stringify({
        overlay: "1.1.0",
        info: { title: "s", version: "1" },
        actions: [{ target: "$.info", update: { summary: "CRM" } }],
      }),
    );

    const rendered = await renderTarget(
      target(["title.yaml", "summary.json"]),
      { root, entry, cache: false, validate: false },
    );

    expect(JSON.parse(rendered.text)).toMatchObject({
      info: { title: "Renamed", summary: "CRM" },
    });
  });

  it("reports overlay files that are not overlays", async () => {
    await writeFile(join(root, "broken.json"), "{");
    await writeFile(join(root, "other.json"), "{}");

    const rendered = await renderTarget(target(["broken.json", "other.json"]), {
      root,
      entry,
      cache: false,
      validate: false,
    });

    expect(rendered.diagnostics.map((diagnostic) => diagnostic.code)).toEqual([
      "overlay-invalid",
      "overlay-invalid",
    ]);
  });

  it("caches the render, and adds schema findings once validate runs", async () => {
    const context = { root, entry, cache: true, validate: false };
    expect((await renderTarget(target(), context)).cached).toBe(false);
    expect((await renderTarget(target(), context)).cached).toBe(true);

    const validated = await renderTarget(target(), {
      ...context,
      validate: true,
    });

    expect(validated.cached).toBe(false);
    expect(
      (await renderTarget(target(), { ...context, validate: true })).cached,
    ).toBe(true);

    const keyed = await renderTarget(target(), {
      ...context,
      entry: { ...entry, cacheKey: "v2" },
    });

    expect(keyed.cached).toBe(false);
  });
});

describe("built-in formats", () => {
  const events = defineApi(defineSupabase(schema), {
    info: { title: "CRM", version: "1.0.0" },
    resources: { customers: true },
    workflows: [
      { id: "list", steps: [{ id: "list", operationId: "listCustomers" }] },
    ],
  });

  it("render AsyncAPI and Arazzo documents that match their official schemas", async () => {
    const targets = resolveTargets(
      [
        { format: "asyncapi" },
        { format: "asyncapi", version: "3.1", output: "asyncapi-3.1.yaml" },
        { format: "arazzo" },
        { format: "arazzo", version: "1.1", output: "arazzo-1.1.json" },
      ],
      formatRegistry(),
      {},
    );

    const rendered = await Promise.all(
      targets.map((each) =>
        renderTarget(each, {
          root,
          entry: { api: events, documents: new Map(), formats: [] },
          cache: false,
          validate: true,
        }),
      ),
    );

    expect(rendered.map((each) => [each.pin, each.diagnostics])).toEqual([
      ["3.0.0", []],
      ["3.1.0", []],
      ["1.0.1", []],
      ["1.1.0", []],
    ]);
    expect(rendered[1]?.text).toMatch(/^asyncapi: 3\.1\.0$/m);
  });
});

describe("loadSpecEntry", () => {
  it("reads formats, a cache key and documents", async () => {
    await writeFile(
      join(root, "entry.mjs"),
      [
        "export const cacheKey = 'k';",
        "export const formats = () => [globalThis.__specFormat, { id: 'nope' }];",
        "export const asyncapi = async () => ({ asyncapi: '3.0.0', info: {} });",
        "export default { openapi: '3.1.0' };",
      ].join("\n"),
    );
    Reflect.set(globalThis, "__specFormat", openapiFormat);
    const loaded = await loadSpecEntry(join(root, "entry.mjs"));
    expect(loaded.cacheKey).toBe("k");
    expect(loaded.formats).toEqual([openapiFormat]);
    expect([...loaded.documents.keys()]).toEqual(["asyncapi", "openapi"]);
    await expect(loadSpecEntry(join(root, "absent.mjs"))).rejects.toThrow(
      "Module not found",
    );
  });

  it("recognizes documents and formats", () => {
    expect(documentFormatId({ arazzo: "1.0.1" })).toBe("arazzo");
    expect(documentFormatId([])).toBeUndefined();
    expect(isDocumentFormat(openapiFormat)).toBe(true);
    expect(isDocumentFormat({ apiVersion: 2 })).toBe(false);
  });
});
