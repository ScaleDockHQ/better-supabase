import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import {
  doctorBaselineCodemod,
  groupedFromMap,
} from "../../src/cli/codemod-doctor-baseline.ts";
import { CODEMODS } from "../../src/cli/codemod.ts";
import { resolveConfig } from "../../src/config/index.ts";

describe("codemod doctor-baseline", () => {
  it("is registered", () => {
    expect(CODEMODS["doctor-baseline"]?.name).toBe("doctor-baseline");
  });

  it("turns { code: { reason, targets } } into grouped entries", () => {
    expect(
      groupedFromMap({
        BS351: { reason: "migrating", targets: ["a.ts"] },
        BS200: { reason: "legacy", targets: ["public.notes"] },
      }),
    ).toEqual({
      groups: [
        { code: "BS351", reason: "migrating", targets: ["a.ts"] },
        { code: "BS200", reason: "legacy", targets: ["public.notes"] },
      ],
    });
  });

  it("names an entry without a reason", () => {
    expect(groupedFromMap({ BS351: { targets: [] } })).toEqual({
      problem: "has an entry for BS351 without a reason and targets",
    });
    expect(groupedFromMap("x")).toHaveProperty("problem");
    expect(groupedFromMap({ BS2: "legacy" })).toEqual({
      problem: "has an entry for BS2 without a reason and targets",
    });
  });
});

describe("doctor-baseline project", () => {
  const run = async (contents: string | undefined) => {
    const root = await mkdtemp(join(tmpdir(), "bs-baseline-"));

    if (contents !== undefined) {
      await writeFile(join(root, "baseline.json"), contents);
    }

    return doctorBaselineCodemod().project!({
      config: resolveConfig(
        { doctor: { baseline: "baseline.json" } } as Parameters<
          typeof resolveConfig
        >[0],
        root,
      ),
      sql: [],
    });
  };

  it("says there is nothing to import without a baseline path", async () => {
    const result = await doctorBaselineCodemod().project!({
      config: resolveConfig({}, "/project"),
      sql: [],
    });

    expect(result).toEqual({
      files: [],
      review: [
        { message: "tooling.doctor.baseline is not set; nothing to import." },
      ],
    });
  });

  it("reports a file that is not JSON", async () => {
    expect((await run(undefined)).review).toEqual([
      { message: "baseline.json could not be read as JSON." },
    ]);
    expect((await run("{")).review).toEqual([
      { message: "baseline.json could not be read as JSON." },
    ]);
  });

  it("leaves a grouped list alone", async () => {
    expect(await run("[]")).toEqual({ files: [], review: [] });
  });

  it("names a map entry without a reason", async () => {
    expect((await run('{"BS1":{}}')).review).toEqual([
      {
        message:
          "baseline.json has an entry for BS1 without a reason and targets.",
      },
    ]);
  });

  it("rewrites a map as the grouped list", async () => {
    const { files } = await run('{"BS1":{"reason":"r","targets":["a"]}}');

    expect(files).toHaveLength(1);
    expect(files[0]!.policy).toBe("edit");
    expect(JSON.parse(files[0]!.contents)).toEqual([
      { code: "BS1", reason: "r", targets: ["a"] },
    ]);
  });
});
