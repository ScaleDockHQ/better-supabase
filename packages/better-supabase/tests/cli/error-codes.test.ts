import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

import type { DoctorContext } from "../../src/cli/doctor/rules.ts";

import catalog from "../../schemas/error-codes.json" with { type: "json" };
import {
  ERROR_CODE_RULES,
  raisesWithoutCode,
} from "../../src/cli/doctor/error-codes.ts";
import { ERROR_CODES, scanErrorCodes } from "../../src/cli/error-codes.ts";

describe("error codes", () => {
  it("matches the codes the SQL modules raise", async () => {
    const scanned = await scanErrorCodes(
      resolve(import.meta.dirname, "../../src/sql"),
    );

    expect(scanned).toEqual(ERROR_CODES);
    expect(catalog).toEqual(ERROR_CODES);
    expect(
      ERROR_CODES.some((entry) => entry.code === "IMPORT_ITEM_INVALID"),
    ).toBe(true);
  });

  it("reports a raise that has no hint", () => {
    expect(
      raisesWithoutCode({
        path: "supabase/schemas/app.sql",
        text: "raise exception 'nope' using errcode = '22023';\n",
      }),
    ).toHaveLength(1);
    expect(
      raisesWithoutCode({
        path: "supabase/schemas/app.sql",
        text: "raise exception 'nope' using errcode = '22023', hint = 'APP_NOPE';\n",
      }),
    ).toEqual([]);
    expect(
      raisesWithoutCode({
        path: "supabase/schemas/app.sql",
        text: "raise exception 'nope'\n  using errcode = '22023', hint = 'APP_NOPE';\n",
      }),
    ).toEqual([]);
  });

  it("skips migrations and the files the blocks wrote (BS627)", async () => {
    const raise = "raise exception 'nope' using errcode = '22023';\n";

    const findings = await ERROR_CODE_RULES[0]!.check({
      sqlFiles: [
        { path: "supabase/migrations/1_app.sql", text: raise },
        {
          path: "supabase/schemas/900_better_supabase_003_audit.sql",
          text: `-- @bsb-block audit\n${raise}`,
        },
        { path: "supabase/schemas/app.sql", text: raise },
      ],
    } as unknown as DoctorContext);

    expect(findings).toHaveLength(1);
  });
});
