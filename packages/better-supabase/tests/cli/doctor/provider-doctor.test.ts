import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import {
  PROVIDER_DOCTOR_RULES,
  providerFindings,
} from "../../../src/cli/doctor/provider-doctor.ts";
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

const runDoctor = (command: readonly string[] | undefined) =>
  PROVIDER_DOCTOR_RULES[0]!.check({
    config: {
      root: process.cwd(),
      authorization:
        command === undefined ? undefined : { doctor: { command } },
    },
  } as unknown as DoctorContext);

describe("BS705 check", () => {
  it("runs nothing without a command", async () => {
    expect(await runDoctor(undefined)).toEqual([]);
  });

  it("reads the findings the command prints, even when it exits non-zero", async () => {
    const script = `console.log(JSON.stringify([{ code: "PD9", message: "m", severity: "info", title: "T", help: "h" }])); process.exit(1)`;

    expect(await runDoctor(["node", "-e", script])).toEqual([
      { severity: "info", title: "T", message: "m", target: "PD9", help: "h" },
    ]);
  });

  it("reports an empty command, silent output and output of another shape", async () => {
    const [empty] = await runDoctor([]);
    const [silent] = await runDoctor(["node", "-e", ""]);
    const [malformed] = await runDoctor(["node", "-e", "console.log('{}')"]);

    expect(empty?.message).toContain("the command is empty");
    expect(silent?.message).toContain("gave no findings: it printed nothing");
    expect(malformed?.message).toContain("printed JSON that is not");
  });

  it("reports the error of a command that cannot start", async () => {
    const [missing] = await runDoctor(["bs-no-such-command-xyz"]);

    expect(missing?.message).toContain("ENOENT");
  });
});
