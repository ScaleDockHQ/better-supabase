import { describe, expect, it } from "vitest";

import type { Finding } from "../../../src/cli/doctor/rules.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import {
  applyBaseline,
  parseBaseline,
  updatedBaseline,
} from "../../../src/cli/doctor/baseline.ts";
import { moduleSnapshotFixture as fixture } from "../fixtures/library.ts";

const snapshot = await parseSnapshot(fixture);
const offline = { snapshot };

const skipped = {
  snapshot,
  database: { skipped: "no database URL" },
  advisors: { skipped: "no database URL" },
};

const finding = (
  code: string,
  target: string,
  severity: Finding["severity"] = "error",
): Finding => ({
  code,
  severity,
  title: `${code} title`,
  message: `${code} at ${target}`,
  target,
  help: "https://bettersupabase.com/docs/cli/doctor",
});

describe("parseBaseline", () => {
  it("reads entries and defaults a missing reason", () => {
    expect(
      parseBaseline(
        JSON.stringify([
          { code: "BS351", target: "src/a.ts", reason: "migrating" },
          { code: "BS200", target: "public.notes" },
        ]),
        "doctor-baseline.json",
      ),
    ).toEqual([
      { code: "BS351", target: "src/a.ts", reason: "migrating" },
      { code: "BS200", target: "public.notes", reason: "" },
    ]);
  });

  it("rejects a file that isn't an array of entries", () => {
    expect(() => parseBaseline("{", "b.json")).toThrow("b.json is not JSON");
    expect(() => parseBaseline("{}", "b.json")).toThrow("must be an array");
    expect(() => parseBaseline('[{"code":"BS1"}]', "b.json")).toThrow(
      "b.json entry 0 needs a string code and target.",
    );
  });
});

describe("applyBaseline", () => {
  const ran = new Set(["BS351", "BS200"]);

  it("leaves out the findings the baseline lists", () => {
    const result = applyBaseline(
      [finding("BS351", "src/a.ts"), finding("BS351", "src/b.ts")],
      [{ code: "BS351", target: "src/a.ts", reason: "" }],
      ran,
      offline,
      "doctor-baseline.json",
    );

    expect(result.accepted).toBe(1);
    expect(result.stale).toEqual([]);
    expect(result.findings.map((item) => item.target)).toEqual(["src/b.ts"]);
  });

  it("fails on an entry no finding matches", () => {
    const result = applyBaseline(
      [],
      [{ code: "BS351", target: "src/gone.ts", reason: "" }],
      ran,
      offline,
      "doctor-baseline.json",
    );

    expect(result.findings).toEqual([
      expect.objectContaining({
        code: "BS351",
        severity: "error",
        target: "src/gone.ts",
        help: "https://bettersupabase.com/docs/cli/doctor#baseline",
      }),
    ]);
  });

  it("keeps entries for checks this run couldn't judge", () => {
    const result = applyBaseline(
      [],
      [
        { code: "BS999", target: "x", reason: "" },
        { code: "BS200", target: "public.notes", reason: "" },
        { code: "BS351", target: "src/gone.ts", reason: "" },
      ],
      ran,
      skipped,
      "doctor-baseline.json",
    );

    expect(result.stale.map((entry) => entry.code)).toEqual(["BS351"]);
  });
});

describe("updatedBaseline", () => {
  it("accepts errors and warnings, keeping reasons and unjudged entries", () => {
    expect(
      updatedBaseline(
        [
          finding("BS351", "src/b.ts"),
          finding("BS351", "src/a.ts"),
          finding("BS200", "public.notes", "warning"),
          finding("BS100", "public.x", "info"),
        ],
        [
          { code: "BS351", target: "src/a.ts", reason: "moving to the client" },
          { code: "BS999", target: "y", reason: "not judged" },
          { code: "BS200", target: "public.old", reason: "" },
        ],
        new Set(["BS351", "BS200"]),
        offline,
      ),
    ).toEqual([
      { code: "BS200", target: "public.notes", reason: "" },
      { code: "BS200", target: "public.old", reason: "" },
      { code: "BS351", target: "src/a.ts", reason: "moving to the client" },
      { code: "BS351", target: "src/b.ts", reason: "moving to the client" },
      { code: "BS999", target: "y", reason: "not judged" },
    ]);
  });
});
