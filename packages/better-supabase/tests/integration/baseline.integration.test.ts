import { rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { env } from "node:process";
import { describe, expect, it } from "vitest";

import { buildBaseline } from "../../src/cli/baseline/build.ts";
import { baselineContext } from "../../src/cli/baseline/stack.ts";
import { parseEnv } from "../../src/cli/env.ts";

// The build starts scratch native stacks, so it runs only when asked for:
// BETTER_SUPABASE_BASELINE_LIVE=1 pnpm --filter better-supabase test:integration
const live = env["BETTER_SUPABASE_BASELINE_LIVE"] === "1";

const root = resolve(import.meta.dirname, "../../../..");

describe.skipIf(!live)("baseline", () => {
  it("builds an artifact that a full replay cannot be told apart from", async () => {
    const out = join(tmpdir(), `bsb-baseline-${String(Date.now())}`);
    const ctx = baselineContext(root, parseEnv(env));

    try {
      // `verify` restores the artifact into a fresh stack, then throws
      // `check_failed` when the pg-delta plan to the stored catalog is not
      // empty, the catalog fingerprint differs or a row count differs.
      const built = await buildBaseline(ctx, {
        withSeed: true,
        out,
        force: true,
        verify: true,
      });

      expect(built.key).toMatch(/^[0-9a-f]{64}$/);
    } finally {
      await rm(out, { recursive: true, force: true });
    }
  }, 900_000);
});
