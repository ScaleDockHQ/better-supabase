import { describe, expect, it } from "vitest";

import { EnvValidationError, parseEnv } from "../../src/env/index.ts";
import { parsePublicEnv } from "../../src/env/public.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co/";
const KEY = "sb_publishable_abc";

describe("parsePublicEnv", () => {
  it("returns what parseEnv returns for the same url and key", () => {
    const parsed = parseEnv({
      SUPABASE_URL: PROJECT_URL,
      SUPABASE_PUBLISHABLE_KEY: KEY,
    });

    expect(parsePublicEnv({ url: PROJECT_URL, publishableKey: KEY })).toEqual({
      url: parsed.env?.url,
      publishableKey: parsed.env?.publishableKey,
    });
  });

  it("names the variable and never the value", () => {
    const failure = (): unknown => {
      try {
        parsePublicEnv({
          url: "http://example.com",
          publishableKey: "eyJhbGci",
        });
      } catch (error) {
        return error;
      }

      return undefined;
    };

    expect(failure()).toBeInstanceOf(EnvValidationError);
    expect(String(failure())).toContain("SUPABASE_URL");
    expect(String(failure())).not.toContain("eyJhbGci");
  });

  it("rejects an empty key and url", () => {
    expect(() => parsePublicEnv({ url: "", publishableKey: "" })).toThrow(
      /SUPABASE_URL: is not set[\s\S]*SUPABASE_PUBLISHABLE_KEY: is not set/,
    );
  });
});
