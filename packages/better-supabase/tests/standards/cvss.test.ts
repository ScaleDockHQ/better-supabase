import { describe, expect, it } from "vitest";

import { cvssSeverity, parseCvss } from "../../src/blocks/advisories/index.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

const score = (vector: string) => {
  const parsed = parseCvss(vector);

  if (!parsed.ok) {
    throw new Error(parsed.error.message);
  }

  return parsed.data;
};

describe("parseCvss", () => {
  it.each([
    ["CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H", 10, "critical"],
    ["CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H", 9.8, "critical"],
    ["CVSS:3.0/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H", 9.8, "critical"],
    ["CVSS:3.1/AV:L/AC:L/PR:L/UI:N/S:U/C:H/I:N/A:N", 5.5, "medium"],
    ["CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:C/C:L/I:L/A:N", 6.1, "medium"],
    ["CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:N/A:N", 0, "none"],
  ] as const)("scores %s as %s", (vector, baseScore, severity) => {
    const parsed = score(vector);

    expect(parsed.baseScore).toBe(baseScore);
    expect(parsed.severity).toBe(severity);
    expect(parsed.metrics["AV"]).toBe(vector.split("AV:")[1]?.charAt(0));
  });

  it("parses a 4.0 vector without scoring it", () => {
    const parsed = score(
      "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:H/VI:H/VA:H/SC:N/SI:N/SA:N",
    );

    expect(parsed.version).toBe("4.0");
    expect(parsed.baseScore).toBeUndefined();
    expect(parsed.severity).toBeUndefined();
    expect(parsed.metrics["VC"]).toBe("H");
  });

  it("refuses a vector it cannot read", () => {
    for (const vector of [
      "",
      "AV:N/AC:L",
      "CVSS:2.0/AV:N/AC:L/Au:N/C:P/I:P/A:P",
      "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H",
      "CVSS:3.1/AV:X/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H",
      "CVSS:3.1/AV:N/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H",
      "CVSS:4.0/AV:N",
    ]) {
      expect({ vector, ok: parseCvss(vector).ok }).toEqual({
        vector,
        ok: false,
      });
    }
  });
});

describe("cvssSeverity", () => {
  it("rates a score by the CVSS 3.1 bands", () => {
    expect(
      [0, 0.1, 3.9, 4, 6.9, 7, 8.9, 9, 10].map((value) => cvssSeverity(value)),
    ).toEqual([
      "none",
      "low",
      "low",
      "medium",
      "medium",
      "high",
      "high",
      "critical",
      "critical",
    ]);
  });
});

describe("cvss spec pin", () => {
  it("names the version the code follows", () => {
    expect(SPEC_PINS.cvss).toBe("3.1");
    expect(SPEC_PINS.cvss4).toBe("4.0");
  });
});
