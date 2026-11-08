import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

/**
 * The CentraKit fixture's config line budget (ADR 0324). The target is under
 * 800 lines now and under 400 once the app files carry its columns. The count
 * only goes down: lower the limit when the config shrinks. Lienlink's 162-line
 * budget has no committed fixture yet, so it is checked by hand against the
 * real repository.
 */
const LIMIT = 800;

describe("the CentraKit fixture config", () => {
  it(`stays under ${String(LIMIT)} lines`, async () => {
    const text = await readFile(
      fileURLToPath(new URL("../better-supabase.config.ts", import.meta.url)),
      "utf-8",
    );

    expect(text.split("\n").length).toBeLessThan(LIMIT);
  });
});
