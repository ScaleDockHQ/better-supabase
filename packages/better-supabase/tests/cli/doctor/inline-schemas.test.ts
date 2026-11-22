import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { INLINE_SCHEMA_RULES } from "../../../src/cli/doctor/inline-schemas.ts";
import { resolveConfig } from "../../../src/config/index.ts";

const NOTE = {
  type: "object",
  required: ["title"],
  properties: {
    title: { type: "string" },
    tags: { items: { type: "string" }, type: "array" },
  },
};

const MODULE = `
const standard = (json) => ({ "~standard": { version: 1, vendor: "test", validate: (value) => ({ value }), ...(json ? { jsonSchema: { input: () => json } } : {}) } });
export const note = standard(${JSON.stringify(NOTE)});
export const plain = standard(undefined);
export const other = 42;
`;

let root: string;

beforeAll(async () => {
  root = await mkdtemp(join(tmpdir(), "bs-inline-"));
  await writeFile(join(root, "schemas.mjs"), MODULE);
});

afterAll(async () => {
  await rm(root, { recursive: true, force: true });
});

const check = INLINE_SCHEMA_RULES[0]!.check;

const GENERATOR_OPTIONS = {
  settings: "./schemas.mjs#note",
  json: { a: "./missing.mjs#x", b: "no-hash" },
};

function context(
  json: Record<string, unknown>,
  settings: unknown,
  options: Record<string, unknown> = GENERATOR_OPTIONS,
): DoctorContext {
  const config = resolveConfig({}, root);

  return {
    config: {
      ...config,
      json,
      blocks: { settings: { options: { schemas: settings } } },
      generators: [
        { name: "other", options: {} },
        { name: "standard-schema", options },
      ],
    } as unknown as DoctorContext["config"],
    snapshot: undefined as unknown as DoctorContext["snapshot"],
    configToml: undefined,
    envFiles: [],
    gitignore: "",
    sources: [],
  };
}

const reordered = {
  properties: {
    tags: { type: "array", items: { type: "string" } },
    title: { type: "string" },
  },
  type: "object",
  required: ["title"],
};

describe("BS704", () => {
  it("names the export an inline gen.json schema repeats, regardless of key order", async () => {
    const findings = await check(
      context(
        { note: { schema: reordered }, other: { schema: { type: "string" } } },
        undefined,
      ),
    );

    expect(findings).toEqual([
      expect.objectContaining({
        target: 'gen.json["note"].schema',
        message: expect.stringContaining('Name it as "./schemas.mjs#note"'),
      }),
    ]);
  });

  it("reads settings schemas per scope and skips wrapped or standard entries", async () => {
    const findings = await check(
      context(
        {},
        {
          user: { prefs: NOTE, wrapped: { schema: NOTE } },
          organization: "not a map",
          platform: { std: { "~standard": {} } },
        },
      ),
    );

    expect(findings.map((finding) => finding.target)).toEqual([
      "blocks.settings.options.schemas.user.prefs",
    ]);
  });

  it("ignores a nested schemas option and returns nothing without inline schemas", async () => {
    expect(await check(context({}, { schemas: {} }))).toEqual([]);
    expect(
      await check(context({ a: { schema: { "~standard": {} } } }, undefined)),
    ).toEqual([]);
  });

  it("reports nothing when no generator names a module", async () => {
    expect(
      await check(
        context({ note: { schema: NOTE } }, undefined, { json: "x" }),
      ),
    ).toEqual([]);
  });
});
