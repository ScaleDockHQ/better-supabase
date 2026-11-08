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
  readonly dataFiles?: readonly { path: string; text: string }[];
  readonly sqlFiles?: readonly { path: string; text: string }[];
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
    dataFiles: state.dataFiles ?? [],
    sqlFiles: state.sqlFiles ?? [],
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

const DATA = "-- @bsb-block-data memberships\n";

describe("BS357 data file insert without a key", () => {
  it("flags an insert that reruns without effect only when it has a key", async () => {
    const findings = await run("BS357", {
      blockNames: [],
      dataFiles: [
        {
          path: "supabase/better-supabase-data/a.sql",
          text: `${DATA}insert into public.roles (name) values ('a');\ninsert into public.roles (name) values ('b') on conflict (name) do nothing;\ninsert into public.roles (name) select 'c' where not exists (select 1 from public.roles);`,
        },
      ],
    });

    expect(findings).toHaveLength(1);
    expect(findings[0]?.location).toEqual({
      file: "supabase/better-supabase-data/a.sql",
      line: 2,
    });
  });

  it("leaves files that are not block data files alone", async () => {
    expect(
      await run("BS357", {
        blockNames: [],
        dataFiles: [{ path: "x.sql", text: "insert into t values (1);" }],
      }),
    ).toEqual([]);
  });
});

describe("BS358 app seed on a block table", () => {
  const dataFiles = [
    {
      path: "supabase/better-supabase-data/a.sql",
      text: `${DATA}insert into "public"."roles" (name) values ('a') on conflict do nothing;`,
    },
  ];

  it("flags an app seed that writes a block-seeded table", async () => {
    const findings = await run("BS358", {
      blockNames: [],
      dataFiles,
      files: [
        {
          path: "supabase/seeds/010.sql",
          text: "insert into roles (name) values ('x');\ninsert into other (a) values (1);",
        },
      ],
    });

    expect(findings).toHaveLength(1);
    expect(findings[0]?.location?.line).toBe(1);
  });

  it("ignores generated sample files and tables no block seeds", async () => {
    expect(
      await run("BS358", {
        blockNames: [],
        dataFiles,
        files: [
          {
            path: "supabase/seeds/900_sample.sql",
            text: `${SAMPLE_FILE_MARKER}\ninsert into roles (name) values ('x');`,
          },
          {
            path: "supabase/seeds/020.sql",
            text: "insert into trade_types values (1);",
          },
        ],
      }),
    ).toEqual([]);
  });
});

describe("BS359 seed function without a locale", () => {
  it("flags a seed_*_defaults function without p_locale", async () => {
    const findings = await run("BS359", {
      blockNames: [],
      sqlFiles: [
        {
          path: "supabase/schemas/a.sql",
          text: "create or replace function better_supabase.seed_tax_defaults(p_tenant uuid, p_variant text) returns void language sql as $$ select 1 $$;\ncreate function better_supabase.seed_x_defaults(p_tenant uuid, p_locale text) returns void language sql as $$ select 1 $$;\ncreate function public.other(p_tenant uuid) returns void language sql as $$ select 1 $$;",
        },
        {
          path: "supabase/migrations/1_a.sql",
          text: "create function seed_old_defaults(p uuid) returns void language sql as $$ select 1 $$;",
        },
      ],
    });

    expect(findings).toHaveLength(1);
    expect(findings[0]?.message).toContain("seed_tax_defaults");
  });
});
