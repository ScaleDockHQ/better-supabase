import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import {
  SAMPLE_FILE_MARKER,
  SEED_RULES,
} from "../../../src/cli/doctor/seeds.ts";

const rule = (code: string) => {
  const found = SEED_RULES.find((each) => each.code === code);

  if (found === undefined) {
    throw new Error(`no rule ${code}`);
  }

  return found;
};

interface SeedState {
  readonly blockNames: readonly string[];
  readonly enabled?: boolean;
  readonly onCreate?: boolean;
  readonly variants?: Record<string, string>;
  readonly file?: string;
  readonly files?: readonly { path: string; text: string }[];
}

function context(state: SeedState): DoctorContext {
  // SAFETY: the seed rules read only blockNames, seed and seedFiles.
  return {
    config: {
      blockNames: state.blockNames,
      seed: {
        defaults: {
          enabled: state.enabled ?? true,
          onCreate: state.onCreate ?? true,
          variants: state.variants ?? {},
        },
        sample: { file: state.file ?? "supabase/seeds/900_sample.sql" },
      },
    },
    seedFiles: state.files ?? [],
  } as unknown as DoctorContext;
}

const run = (code: string, state: SeedState) =>
  rule(code).check(context(state));

describe("BS354 defaults not applied", () => {
  // `tax` declares defaults (tax-seeds.ts) and `memberships` is the base.
  const base = ["memberships", "organizations", "tax"];

  it("asks for the seeds block when it is missing", async () => {
    const findings = await run("BS354", { blockNames: base });

    expect(findings).toHaveLength(1);
    expect(findings[0]?.message).toContain("seeds block is not installed");
    expect(findings[0]?.target).toBe("blocks.seeds");
  });

  it("reports the hook turned off", async () => {
    const off = await run("BS354", {
      blockNames: [...base, "seeds"],
      enabled: false,
    });

    const quiet = await run("BS354", {
      blockNames: [...base, "seeds"],
      onCreate: false,
    });

    expect(off[0]?.message).toContain("is false");
    expect(quiet[0]?.message).toContain("onCreate off");
  });

  it("stays quiet when applied, or when nothing declares defaults", async () => {
    expect(await run("BS354", { blockNames: [...base, "seeds"] })).toEqual([]);
    expect(await run("BS354", { blockNames: ["memberships"] })).toEqual([]);
  });
});

describe("BS355 undeclared variant", () => {
  it("names an unknown block and an undeclared variant", async () => {
    const findings = await run("BS355", {
      blockNames: [],
      variants: { ghost: "x", cases: "nope" },
    });

    expect(findings.map((finding) => finding.target)).toEqual([
      "database.seed.defaults.variants.ghost",
      "database.seed.defaults.variants.cases",
    ]);
    expect(findings[0]?.message).toContain("not a block");
    expect(findings[1]?.message).toContain("declares no variants");
  });

  it("accepts no variants", async () => {
    expect(await run("BS355", { blockNames: [] })).toEqual([]);
  });
});

describe("BS356 sample file outside the configured output", () => {
  const sample = `${SAMPLE_FILE_MARKER} (seed 1, size m). Do not edit.\n`;

  it("hints at a sample file the config does not point to", async () => {
    const findings = await run("BS356", {
      blockNames: [],
      files: [
        { path: "supabase/seeds/000_better_supabase.sql", text: "-- app\n" },
        { path: "supabase/seeds/950_demo.sql", text: sample },
      ],
    });

    expect(findings.map((finding) => finding.target)).toEqual([
      "supabase/seeds/950_demo.sql",
    ]);
  });

  it("stays quiet at the configured output", async () => {
    expect(
      await run("BS356", {
        blockNames: [],
        files: [{ path: "supabase/seeds/900_sample.sql", text: sample }],
      }),
    ).toEqual([]);
    expect(await run("BS356", { blockNames: [] })).toEqual([]);
  });
});
