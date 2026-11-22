import { beforeEach, describe, expect, it, vi } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import {
  loadSupabaseCliCheck,
  parseConfigValidation,
  SUPABASE_CLI_RULES,
} from "../../../src/cli/doctor/supabase-cli.ts";
import { supabaseCli } from "../../../src/cli/exec.ts";
import { supabaseConfigFromText } from "../../../src/cli/supabase-config.ts";

vi.mock(import("../../../src/cli/exec.ts"), async (importOriginal) => ({
  ...(await importOriginal()),
  supabaseCli: vi.fn<typeof supabaseCli>(),
}));

const output = (stdout: string, code = 0) => ({ code, stdout, stderr: "" });

const REPORT = JSON.stringify({
  valid: false,
  file: "supabase/config.toml",
  errors: [
    {
      code: "removed_key",
      path: "inbucket",
      reason: "removed",
      help: "rename [inbucket] to [local_smtp]",
      line: 5,
      column: 2,
    },
    { code: "invalid_value", path: "db.major_version", reason: "unsupported" },
  ],
  warnings: [{ code: "w", path: "api.x", reason: "odd" }],
});

function check(code: string, context: Partial<DoctorContext>) {
  const rule = SUPABASE_CLI_RULES.find((candidate) => candidate.code === code)!;

  // SAFETY: the rules read only the fields a test sets.
  return rule.check(context as DoctorContext);
}

describe("parseConfigValidation", () => {
  it("reads errors and warnings with their position", () => {
    expect(parseConfigValidation(REPORT)?.problems).toHaveLength(3);
    expect(parseConfigValidation(REPORT)?.problems[0]).toMatchObject({
      severity: "error",
      path: "inbucket",
      line: 5,
    });
  });

  it("rejects output that is not a validation report", () => {
    expect(parseConfigValidation("nope")).toBeUndefined();
    expect(parseConfigValidation('{"_tag":"Error"}')).toBeUndefined();
  });
});

describe("loadSupabaseCliCheck", () => {
  beforeEach(() => {
    vi.mocked(supabaseCli).mockReset();
  });

  it("validates with CLI 3.2.0 or newer", async () => {
    vi.mocked(supabaseCli)
      .mockResolvedValueOnce(output("3.2.0\n"))
      .mockResolvedValueOnce(output(REPORT, 1));

    const result = await loadSupabaseCliCheck("/p", {});

    expect(result).toMatchObject({ version: "3.2.0" });
    expect("validation" in result && result.validation.file).toBe(
      "supabase/config.toml",
    );
  });

  it("does not run config validate on an older CLI", async () => {
    vi.mocked(supabaseCli).mockResolvedValueOnce(output("3.1.9\n"));

    expect(await loadSupabaseCliCheck("/p", {})).toEqual({ version: "3.1.9" });
    expect(supabaseCli).toHaveBeenCalledOnce();
  });

  it("skips when no CLI runs", async () => {
    vi.mocked(supabaseCli).mockRejectedValueOnce(new Error("not found"));

    expect(await loadSupabaseCliCheck("/p", {})).toEqual({
      skipped: "not found",
    });
  });
});

describe("BS710", () => {
  it("flags a CLI below 3.2.0", async () => {
    expect(
      await check("BS710", { supabaseCli: { version: "3.1.0" } }),
    ).toHaveLength(1);
    expect(await check("BS710", { supabaseCli: { version: "3.2.0" } })).toEqual(
      [],
    );
    expect(await check("BS710", { supabaseCli: { skipped: "x" } })).toEqual([]);
    expect(await check("BS710", {})).toEqual([]);
  });
});

describe("BS711", () => {
  it("reports each problem with file and line, and leaves db.major_version to BS712", async () => {
    const findings = await check("BS711", {
      supabaseCli: {
        version: "3.2.0",
        validation: parseConfigValidation(REPORT)!,
      },
    });

    expect(findings).toHaveLength(2);
    expect(findings[0]).toMatchObject({
      severity: "error",
      location: { file: "supabase/config.toml", line: 5 },
    });
    expect(findings[0]!.message).toContain("rename [inbucket] to [local_smtp]");
    expect(findings[1]).toMatchObject({ severity: "warning" });
  });
});

describe("BS712", () => {
  const toml = (major: number) =>
    supabaseConfigFromText(`[db]\nmajor_version = ${String(major)}\n`);

  it("errors on 13, warns on 14 and accepts 15 and later", async () => {
    expect(await check("BS712", { configToml: toml(13) })).toMatchObject([
      { severity: "error", location: { line: 2 } },
    ]);
    expect(await check("BS712", { configToml: toml(14) })).toMatchObject([
      { severity: "warning" },
    ]);
    expect(await check("BS712", { configToml: toml(17) })).toEqual([]);
    expect(await check("BS712", {})).toEqual([]);
  });
});
