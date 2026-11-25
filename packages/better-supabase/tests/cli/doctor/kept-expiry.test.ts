import { describe, expect, it } from "vitest";

import type { DoctorContext, TextFile } from "../../../src/cli/doctor/rules.ts";

import { KEPT_EXPIRY_RULES } from "../../../src/cli/doctor/kept-expiry.ts";

const KEPT: TextFile = {
  path: "src/lib/reads.ts",
  text: 'export const read = bsb.kept(async () => 1, { name: "a", tables: ["notes"] });',
};

const run = (code: string, sources: readonly TextFile[]) => {
  const rule = KEPT_EXPIRY_RULES.find((entry) => entry.code === code);
  // SAFETY: both rules read only `sources`.
  const findings = rule?.check({ sources } as unknown as DoctorContext);

  if (!Array.isArray(findings)) {
    throw new TypeError("the rules run synchronously");
  }

  return findings;
};

describe("BS648", () => {
  it("names updateTag and revalidateTag beside a kept read", () => {
    const findings = run("BS648", [
      KEPT,
      {
        path: "src/app/actions.ts",
        text: [
          'import { updateTag, revalidateTag as rt } from "next/cache";',
          'updateTag("bsb:notes");',
          'rt("bsb:notes", { expire: 0 });',
        ].join("\n"),
      },
    ]);

    expect(findings.map((finding) => finding.location?.line)).toEqual([2, 3]);
    expect(findings[0]?.message).toContain("bsb.expireTags");
  });

  it("is quiet without a kept read", () => {
    expect(
      run("BS648", [
        {
          path: "src/a.ts",
          text: 'import { updateTag } from "next/cache"; updateTag("x");',
        },
      ]),
    ).toEqual([]);
  });
});

describe("BS649", () => {
  const refresh: TextFile = {
    path: "src/app/actions.ts",
    text: 'import { refresh } from "next/cache";\nexport async function save() { refresh(); }',
  };

  it("flags refresh() that expires nothing", () => {
    expect(run("BS649", [KEPT, refresh])).toHaveLength(1);
  });

  it("accepts a file that expires tags", () => {
    expect(
      run("BS649", [
        KEPT,
        { ...refresh, text: `${refresh.text}\nawait bsb.expireTags([]);` },
      ]),
    ).toEqual([]);
  });
});
