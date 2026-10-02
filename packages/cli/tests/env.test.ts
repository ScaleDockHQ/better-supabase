import { describe, expect, it } from "vitest";

import { parseEnv } from "../src/env.ts";
import { CliError } from "../src/errors.ts";

describe("parseEnv", () => {
  it("keeps the variables the CLI reads and treats empty ones as unset", () => {
    expect(
      parseEnv({
        DATABASE_URL: "postgresql://u@h/db",
        SUPABASE_ACCESS_TOKEN: "sbp_test",
        CI: "",
        UNRELATED: "x",
      }),
    ).toMatchObject({
      DATABASE_URL: "postgresql://u@h/db",
      SUPABASE_ACCESS_TOKEN: "sbp_test",
      CI: undefined,
    });
  });

  it("reports a malformed URL as env_invalid with one issue per variable", () => {
    let caught: unknown;
    try {
      parseEnv({ DATABASE_URL: "not a url", SUPABASE_API_URL: "nope" });
    } catch (error) {
      caught = error;
    }
    expect(caught).toBeInstanceOf(CliError);
    expect(caught).toMatchObject({
      code: "env_invalid",
      exitCode: 2,
      problem: {
        issues: [
          expect.stringMatching(/^DATABASE_URL: must be a URL/),
          expect.stringMatching(/^SUPABASE_API_URL: must be a URL/),
        ],
      },
    });
  });
});
