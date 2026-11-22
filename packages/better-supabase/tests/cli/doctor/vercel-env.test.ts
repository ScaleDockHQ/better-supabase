import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import {
  VERCEL_CODES,
  VERCEL_ENV_RULES,
  vercelEnvPath,
} from "../../../src/cli/doctor/vercel-env.ts";

const rule = (code: string) =>
  VERCEL_ENV_RULES.find((candidate) => candidate.code === code)!;

const REF_A = "aaaaaaaaaaaaaaaaaaaa";
const REF_B = "bbbbbbbbbbbbbbbbbbbb";

const file = (environment: string, text: string) => ({
  environment,
  file: { path: vercelEnvPath(environment), text },
});

const context = (
  vercelEnv: readonly ReturnType<typeof file>[] | undefined,
): DoctorContext =>
  // SAFETY: the Vercel rules read only context.vercelEnv.
  ({ vercelEnv }) as unknown as DoctorContext;

const full = (ref: string) =>
  [
    `SUPABASE_URL="https://${ref}.supabase.co"`,
    'SUPABASE_PUBLISHABLE_KEY="sb_publishable_x"',
    'POSTGRES_URL=""',
  ].join("\n");

describe("vercel env rules", () => {
  it("lists the codes and the pulled path", () => {
    expect([...VERCEL_CODES].toSorted()).toEqual(["BS513", "BS514", "BS515"]);
    expect(vercelEnvPath("preview")).toBe(".vercel/.env.preview.local");
  });

  it("does nothing without --vercel", async () => {
    for (const code of VERCEL_CODES) {
      expect(await rule(code).check(context(undefined))).toEqual([]);
    }
  });
});

describe("BS513", () => {
  it("points at vercel pull when no file exists", async () => {
    const findings = await rule("BS513").check(context([]));

    expect(findings).toHaveLength(1);
    expect(findings[0]?.message).toMatch(/vercel pull/);
  });

  it("names a missing URL and a missing key per environment", async () => {
    const findings = await rule("BS513").check(
      context([
        file("production", full(REF_A)),
        file("development", "OTHER=1"),
      ]),
    );

    expect(findings.map((finding) => finding.target)).toEqual(
      expect.arrayContaining([
        "development:SUPABASE_URL",
        "development:SUPABASE_PUBLISHABLE_KEY",
      ]),
    );
    expect(
      findings.some((finding) => finding.target?.startsWith("production:")),
    ).toBe(false);
  });

  it("calls out a legacy-only key", async () => {
    const findings = await rule("BS513").check(
      context([
        file(
          "preview",
          `SUPABASE_URL="https://${REF_B}.supabase.co"\nNEXT_PUBLIC_SUPABASE_ANON_KEY="eyJ"`,
        ),
      ]),
    );

    expect(findings).toHaveLength(1);
    expect(findings[0]?.message).toMatch(/legacy name/);
  });

  it("names a variable that production sets and preview lacks", async () => {
    const findings = await rule("BS513").check(
      context([
        file("production", `${full(REF_A)}\nSUPABASE_SECRET_KEY=""`),
        file("preview", full(REF_B)),
      ]),
    );

    expect(findings.map((finding) => finding.target)).toEqual([
      "preview:SUPABASE_SECRET_KEY",
    ]);
  });

  it("accepts complete environments", async () => {
    expect(
      await rule("BS513").check(
        context([
          file("production", full(REF_A)),
          file("preview", full(REF_B)),
        ]),
      ),
    ).toEqual([]);
  });
});

describe("BS514", () => {
  it("reports a secret under a public prefix, by name and by value", async () => {
    const findings = await rule("BS514").check(
      context([
        file(
          "production",
          [
            'NEXT_PUBLIC_SUPABASE_SECRET_KEY=""',
            'NEXT_PUBLIC_DATABASE_URL=""',
            'VITE_KEY="sb_secret_abc"',
            'NEXT_PUBLIC_SUPABASE_URL="https://x.supabase.co"',
          ].join("\n"),
        ),
      ]),
    );

    expect(findings.map((finding) => finding.target)).toEqual([
      "production:NEXT_PUBLIC_SUPABASE_SECRET_KEY",
      "production:NEXT_PUBLIC_DATABASE_URL",
      "production:VITE_KEY",
    ]);
    expect(JSON.stringify(findings)).not.toContain("sb_secret_abc");
  });
});

describe("BS515", () => {
  it("reports one project behind preview and production", async () => {
    const findings = await rule("BS515").check(
      context([file("production", full(REF_A)), file("preview", full(REF_A))]),
    );

    expect(findings.map((finding) => finding.target)).toEqual([
      "preview:SUPABASE_URL",
    ]);
  });

  it("accepts two projects and skips a hidden URL", async () => {
    expect(
      await rule("BS515").check(
        context([
          file("production", full(REF_A)),
          file("preview", full(REF_B)),
        ]),
      ),
    ).toEqual([]);
    expect(
      await rule("BS515").check(
        context([
          file("production", full(REF_A)),
          file("preview", 'SUPABASE_URL=""'),
        ]),
      ),
    ).toEqual([]);
  });
});
