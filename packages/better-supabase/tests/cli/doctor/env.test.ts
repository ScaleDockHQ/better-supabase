import { chmod, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { loadStackEnvCheck, ENV_RULES } from "../../../src/cli/doctor/env.ts";
import { PROCESS_ENV, parseEnv } from "../../../src/cli/env.ts";

const STATUS = {
  API_URL: "http://127.0.0.1:55021",
  PUBLISHABLE_KEY: "sb_publishable_stack",
  SECRET_KEY: "sb_secret_stack",
};

let root: string;

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), "better-supabase-stack-env-"));
});

afterEach(async () => {
  await rm(root, { recursive: true, force: true });
});

async function fakeSupabase(script: string): Promise<string> {
  const bin = join(root, "fake-supabase");
  await writeFile(bin, `#!/bin/sh\n${script}\n`);
  await chmod(bin, 0o755);

  return bin;
}

const check = (stackEnv: DoctorContext["stackEnv"]) => {
  const rule = ENV_RULES.find((candidate) => candidate.code === "BS503")!;

  // SAFETY: BS503 reads only stackEnv from the context.
  return rule.check({ stackEnv } as DoctorContext);
};

describe("BS503", () => {
  it("names each stale variable with redacted values", async () => {
    const bin = await fakeSupabase(`echo '${JSON.stringify(STATUS)}'`);

    const stackEnv = await loadStackEnvCheck(
      root,
      parseEnv({
        SUPABASE_BIN: bin,
        SUPABASE_URL: "http://127.0.0.1:54321",
        NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_old",
        SUPABASE_SECRET_KEY: "sb_secret_stack",
      }),
    );

    const findings = await check(stackEnv);

    expect(findings.map((finding) => finding.target)).toEqual([
      "SUPABASE_URL",
      "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
    ]);
    expect(findings[0]?.message).toContain(
      "SUPABASE_URL is exported as 127.0.0.1:54321, but the running stack has 127.0.0.1:55021.",
    );
    expect(JSON.stringify(findings)).not.toContain("sb_publishable_");
  });

  it("never starts supabase status when no SUPABASE_* variable is exported", async () => {
    const bin = await fakeSupabase("exit 99");

    expect(
      await loadStackEnvCheck(
        root,
        parseEnv({ SUPABASE_BIN: bin, PATH: "/bin" }),
      ),
    ).toEqual({ skipped: "No SUPABASE_* variable is exported." });
    expect(await loadStackEnvCheck(root, {})).toMatchObject({
      skipped: expect.any(String),
    });
  });

  it("skips quietly when the stack is down or the CLI is missing", async () => {
    const down = await fakeSupabase("exit 1");

    const stopped = await loadStackEnvCheck(
      root,
      parseEnv({ SUPABASE_BIN: down, SUPABASE_URL: "http://127.0.0.1:54321" }),
    );

    expect(stopped).toEqual({ skipped: "The local stack is not running." });
    expect(await check(stopped)).toEqual([]);

    const missing = await loadStackEnvCheck(root, {
      SUPABASE_BIN: join(root, "nope"),
      [PROCESS_ENV]: { SUPABASE_URL: "http://127.0.0.1:54321" },
    });

    expect(missing).toMatchObject({
      skipped: expect.stringContaining("Supabase CLI"),
    });
  });
});
