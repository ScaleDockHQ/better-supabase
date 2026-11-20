import { describe, expect, it } from "vitest";

import type {
  BaselineManifest,
  BaselineVersions,
  HashedFile,
} from "../../../src/cli/baseline/key.ts";

import {
  BASELINE_FORMAT,
  digest,
  matchBaseline,
  matchSeed,
  schemaKey,
  seedKey,
} from "../../../src/cli/baseline/key.ts";

const versions: BaselineVersions = {
  bsb: "1.0.0",
  supabaseCli: "3.1.0",
  postgres: "17.6",
  engine: "1",
};

const file = (name: string, sha256: string): HashedFile => ({
  file: `supabase/migrations/${name}`,
  sha256,
});

const migrations = [
  file("20240101000000_a.sql", "a"),
  file("20240102000000_b.sql", "b"),
];

function manifest(seed?: BaselineManifest["seed"]): BaselineManifest {
  const key = schemaKey(migrations, versions);

  return {
    format: BASELINE_FORMAT,
    key,
    createdAt: "2026-11-20T00:00:00.000Z",
    versions,
    migrations,
    counts: {},
    fingerprint: {},
    ...(seed === undefined ? {} : { seed }),
  };
}

describe("keys", () => {
  it("does not depend on the order of the digest parts being merged", () => {
    expect(digest(["ab", "c"])).not.toBe(digest(["a", "bc"]));
  });

  it("changes with an edited migration or a tool version", () => {
    const base = schemaKey(migrations, versions);

    expect(schemaKey(migrations, versions)).toBe(base);
    expect(
      schemaKey([migrations[0]!, file("20240102000000_b.sql", "x")], versions),
    ).not.toBe(base);
    expect(schemaKey(migrations, { ...versions, postgres: "17.7" })).not.toBe(
      base,
    );
  });
});

describe("matchBaseline", () => {
  it("accepts the same migrations with nothing pending", () => {
    expect(matchBaseline(manifest(), migrations, versions)).toEqual({
      ok: true,
      pending: [],
    });
  });

  it("lists migrations dated after the last one as pending", () => {
    const current = [...migrations, file("20240103000000_c.sql", "c")];

    expect(matchBaseline(manifest(), current, versions)).toEqual({
      ok: true,
      pending: ["20240103000000_c.sql"],
    });
  });

  it.each([
    [
      "an edited migration",
      [migrations[0]!, file("20240102000000_b.sql", "x")],
    ],
    ["a removed migration", [migrations[0]!]],
    [
      "an older-dated migration",
      [...migrations, file("20231231000000_z.sql", "z")],
    ],
  ])("rejects %s", (_name, current) => {
    expect(matchBaseline(manifest(), current, versions).ok).toBe(false);
  });

  it("rejects another Postgres or CLI version", () => {
    expect(
      matchBaseline(manifest(), migrations, { ...versions, postgres: "18.0" })
        .ok,
    ).toBe(false);
    expect(
      matchBaseline(manifest(), migrations, {
        ...versions,
        supabaseCli: "3.2.0",
      }).ok,
    ).toBe(false);
  });

  it("ignores the diff engine version", () => {
    expect(
      matchBaseline(manifest(), migrations, { ...versions, engine: "2" }).ok,
    ).toBe(true);
  });

  it("rejects an older format", () => {
    expect(
      matchBaseline({ ...manifest(), format: 0 }, migrations, versions).ok,
    ).toBe(false);
  });
});

describe("matchSeed", () => {
  const seeds = [{ file: "supabase/seeds/1.sql", sha256: "s" }];
  const ok = { ok: true, pending: [] } as const;

  const withSeed = (): BaselineManifest => {
    const base = manifest();

    return manifest({
      key: seedKey(base.key, seeds),
      files: seeds,
      counts: {},
      objects: 0,
      fingerprint: {},
    });
  };

  it("accepts unchanged seeds", () => {
    expect(matchSeed(withSeed(), seeds, ok)).toBeUndefined();
  });

  it("explains a missing seed snapshot", () => {
    expect(matchSeed(manifest(), seeds, ok)).toContain("--with-seed");
  });

  it("refuses when migrations are pending, because they run before the seeds", () => {
    expect(
      matchSeed(withSeed(), seeds, { ok: true, pending: ["x.sql"] }),
    ).toContain("migrations");
  });

  it("refuses changed seeds", () => {
    expect(
      matchSeed(
        withSeed(),
        [{ file: "supabase/seeds/1.sql", sha256: "t" }],
        ok,
      ),
    ).toContain("changed");
  });
});
