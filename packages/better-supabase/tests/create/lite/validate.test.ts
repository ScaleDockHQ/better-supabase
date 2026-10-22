import { describe, expect, it } from "vitest";

import { previewFiles } from "../../../src/create/index.ts";
import { validateDesign } from "../../../src/create/lite/index.ts";
import { presetSpec, namedPreset } from "../../../src/preset/index.ts";

const files = (name: "saas" | "projects") =>
  previewFiles(presetSpec(namedPreset(name)));

describe("validateDesign", () => {
  it("applies the SaaS preset cleanly", async () => {
    const result = await validateDesign(files("saas"));

    expect(result.issues).toEqual([]);
    expect(result.skipped).toEqual([]);
    expect(result.ok).toBe(true);
  }, 60_000);

  it("skips modules that need extensions PGlite lacks", async () => {
    const result = await validateDesign(files("projects"));

    expect(result.ok).toBe(true);
    expect(result.skipped.map((each) => each.module).toSorted()).toEqual([
      "jobs",
      "time-tracking",
    ]);
  }, 60_000);

  it("reports SQL Postgres rejects", async () => {
    const result = await validateDesign([
      {
        path: "a.sql",
        module: "a",
        contents: "create table public.t (id uuid);",
      },
      {
        path: "b.sql",
        module: "b",
        contents: "create table public.t (id uuid);",
      },
    ]);

    expect(result.ok).toBe(false);
    expect(result.tables).toBe(1);
    expect(result.issues).toMatchObject([
      {
        module: "b",
        path: "b.sql",
        message: expect.stringContaining("already exists"),
      },
    ]);
  }, 60_000);
});
