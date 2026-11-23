import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { DoctorValues } from "../../../src/cli/commands/doctor.ts";
import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { doctorCommand, runDoctor } from "../../../src/cli/commands/doctor.ts";
import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { parseCommandArgs } from "../../../src/cli/core/command.ts";
import {
  PROVIDER_DOCTOR_RULES,
  providerFindings,
} from "../../../src/cli/doctor/provider-doctor.ts";
import { RULES } from "../../../src/cli/doctor/rules.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { snapshotFixture as fixture } from "../fixtures/library.ts";

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

const runRule = (command: readonly string[] | undefined) =>
  PROVIDER_DOCTOR_RULES[0]!.check({
    config: {
      root: process.cwd(),
      authorization:
        command === undefined ? undefined : { doctor: { command } },
    },
  } as unknown as DoctorContext);

describe("BS705 check", () => {
  it("runs nothing without a command", async () => {
    expect(await runRule(undefined)).toEqual([]);
  });

  it("reads the findings the command prints, even when it exits non-zero", async () => {
    const script = `console.log(JSON.stringify([{ code: "PD9", message: "m", severity: "info", title: "T", help: "h" }])); process.exit(1)`;

    expect(await runRule(["node", "-e", script])).toEqual([
      { severity: "info", title: "T", message: "m", target: "PD9", help: "h" },
    ]);
  });

  it("reports an empty command, silent output and output of another shape", async () => {
    const [empty] = await runRule([]);
    const [silent] = await runRule(["node", "-e", ""]);
    const [malformed] = await runRule(["node", "-e", "console.log('{}')"]);

    expect(empty?.message).toContain("the command is empty");
    expect(silent?.message).toContain("gave no findings: it printed nothing");
    expect(malformed?.message).toContain("printed JSON that is not");
  });

  it("reports the error of a command that cannot start", async () => {
    const [missing] = await runRule(["bs-no-such-command-xyz"]);

    expect(missing?.message).toContain("ENOENT");
  });
});

describe("the provider's doctor command", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-provider-doctor-"));
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  const run = async (
    command: string[],
    timeoutMs?: number,
    extra: string[] = [],
  ) =>
    runDoctor(
      resolveConfig(
        {
          // SAFETY: only the fields doctor reads are set.
          authorization: {
            apiVersion: 1,
            name: "stub",
            functions: {},
            doctor: {
              command,
              ...(timeoutMs === undefined ? {} : { timeoutMs }),
            },
          },
        } as never,
        root,
      ),
      parseCommandArgs(doctorCommand, [
        "--only",
        "BS705",
        "--json",
        ...extra,
      ]) as DoctorValues,
      {},
      {
        snapshot: await parseSnapshot(fixture),
        database: { skipped: "no database URL" },
        advisors: { skipped: "no database URL" },
      },
    );

  it("names authorization.doctor.timeoutMs when the command times out", async () => {
    const result = await run(
      [process.execPath, "-e", "setTimeout(() => {}, 10000)"],
      200,
    );

    const found = (
      result.data as { findings: { code: string; message: string }[] }
    ).findings;

    expect(found).toHaveLength(1);
    expect(found[0]).toMatchObject({ code: "BS705" });
    expect(found[0]?.message).toContain("authorization.doctor.timeoutMs");
  });

  it("fails the run under the default --fail-on for a provider error", async () => {
    const output = JSON.stringify({
      findings: [{ code: "PD001", severity: "error", message: "broken" }],
    });

    const result = await run([
      process.execPath,
      "-e",
      `console.log(${JSON.stringify(output)})`,
    ]);

    expect(result.code).not.toBe(0);
  });
});
