import { describe, expect, it } from "vitest";

import { providerFindings } from "../../../src/cli/doctor/provider-doctor.ts";
import { RULES } from "../../../src/cli/doctor/rules.ts";

describe("BS705", () => {
  it("is registered", () => {
    expect(RULES.some((rule) => rule.code === "BS705")).toBe(true);
  });

  it("reads findings from an object or a list", () => {
    const entry = {
      code: "PD001",
      severity: "error",
      message: "m",
      target: "public.notes",
    };

    const expected = [
      expect.objectContaining({
        severity: "error",
        target: "PD001 public.notes",
        title: "PD001",
      }),
    ];

    expect(providerFindings(JSON.stringify({ findings: [entry] }))).toEqual(
      expected,
    );
    expect(providerFindings(JSON.stringify([entry]))).toEqual(expected);
  });

  it("rejects output of another shape", () => {
    expect(providerFindings("nope")).toBeUndefined();
    expect(
      providerFindings(JSON.stringify({ findings: [{ code: 1 }] })),
    ).toBeUndefined();
  });

  it("defaults a missing severity to warning", () => {
    expect(
      providerFindings(JSON.stringify([{ code: "PD2", message: "m" }]))?.[0]
        ?.severity,
    ).toBe("warning");
  });
});
