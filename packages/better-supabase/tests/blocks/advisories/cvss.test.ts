import { describe, expect, it } from "vitest";

import {
  cvssSeverity,
  parseCvss,
} from "../../../src/blocks/advisories/cvss.ts";

const V31 = "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H";

describe("cvssSeverity", () => {
  it("rates every band", () => {
    expect(cvssSeverity(0)).toBe("none");
    expect(cvssSeverity(3.9)).toBe("low");
    expect(cvssSeverity(4)).toBe("medium");
    expect(cvssSeverity(6.9)).toBe("medium");
    expect(cvssSeverity(7)).toBe("high");
    expect(cvssSeverity(8.9)).toBe("high");
    expect(cvssSeverity(9)).toBe("critical");
  });
});

describe("parseCvss scoring", () => {
  it("scores 3.1 and 3.0 vectors", () => {
    expect(parseCvss(` ${V31} `).data).toMatchObject({
      version: "3.1",
      baseScore: 9.8,
      severity: "critical",
    });
    expect(parseCvss(V31.replace("3.1", "3.0")).data?.baseScore).toBe(9.8);
  });

  it("scores a changed scope and low privileges", () => {
    expect(
      parseCvss("CVSS:3.1/AV:N/AC:L/PR:L/UI:R/S:C/C:L/I:L/A:N").data?.baseScore,
    ).toBeGreaterThan(4);
    expect(
      parseCvss("CVSS:3.1/AV:L/AC:H/PR:H/UI:R/S:C/C:H/I:H/A:H").data?.baseScore,
    ).toBeGreaterThan(6);
  });

  it("scores zero when there is no impact", () => {
    expect(
      parseCvss("CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:N").data,
    ).toMatchObject({ baseScore: 0, severity: "none" });
  });

  it("covers whole-number and fractional rounding in 3.1", () => {
    expect(
      parseCvss("CVSS:3.1/AV:P/AC:H/PR:H/UI:R/S:U/C:L/I:N/A:N").data?.baseScore,
    ).toBeDefined();
    expect(
      parseCvss("CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:C/C:L/I:N/A:N/E:H").data
        ?.metrics["E"],
    ).toBe("H");
  });

  it("parses a 4.0 vector without a score", () => {
    const vector =
      "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N/E:A";

    expect(parseCvss(vector).data).toMatchObject({
      version: "4.0",
      baseScore: undefined,
      severity: undefined,
    });
  });
});

describe("parseCvss validation", () => {
  const bad = (input: string): string | undefined =>
    parseCvss(input).error?.message;

  it("refuses a bad prefix", () => {
    expect(bad("AV:N")).toMatch(/starts with/u);
    expect(bad("")).toMatch(/starts with/u);
  });

  it("refuses bad pairs and repeats", () => {
    expect(bad(`${V31}/X`)).toMatch(/not a CVSS metric/u);
    expect(bad(`${V31}/X:1:2`)).toMatch(/not a CVSS metric/u);
    expect(bad(`${V31}/ABCD:1`)).toMatch(/not a CVSS metric/u);
    expect(bad(`${V31}/AV:N`)).toMatch(/twice/u);
  });

  it("refuses missing, wrong and unknown metrics", () => {
    expect(bad("CVSS:3.1/AV:N")).toMatch(/missing/u);
    expect(bad(V31.replace("AV:N", "AV:Z"))).toMatch(/not a value/u);
    expect(bad(`${V31}/QQ:N`)).toMatch(/not a CVSS metric/u);
    expect(bad("CVSS:4.0/AV:N")).toMatch(/missing/u);
  });
});
