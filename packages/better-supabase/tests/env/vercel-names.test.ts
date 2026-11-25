import { describe, expect, it } from "vitest";

import { getEnv, projectRefOf, withEnvPrefix } from "../../src/env/index.ts";

describe("projectRefOf", () => {
  it("reads the ref of a hosted URL only", () => {
    expect(projectRefOf("https://abcdefghijklmnopqrst.supabase.co")).toBe(
      "abcdefghijklmnopqrst",
    );
    expect(projectRefOf("http://127.0.0.1:54321")).toBeUndefined();
    expect(projectRefOf("https://auth.example.com")).toBeUndefined();
    expect(projectRefOf("nope")).toBeUndefined();
  });
});

describe("withEnvPrefix", () => {
  it("lets a prefixed name replace the plain one and skips empty values", () => {
    const merged = withEnvPrefix(
      {
        SUPABASE_URL: "https://plain.example",
        DB1_SUPABASE_URL: "https://prefixed.example",
        DB1_SUPABASE_SECRET_KEY: "",
        OTHER: "x",
      },
      "DB1_",
    );

    expect(merged["SUPABASE_URL"]).toBe("https://prefixed.example");
    expect(merged["SUPABASE_SECRET_KEY"]).toBeUndefined();
    expect(merged["OTHER"]).toBe("x");
  });

  it("rejects a prefix Vercel would not accept", () => {
    expect(() => withEnvPrefix({}, "1DB")).toThrow(TypeError);
    expect(() => withEnvPrefix({}, "DB-1")).toThrow(/prefix/);
  });
});

describe("getEnv with the integration's names", () => {
  const keys = {
    NEXT_PUBLIC_SUPABASE_URL: "https://abcdefghijklmnopqrst.supabase.co",
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_x",
  };

  it("reads a custom prefix", () => {
    const env = getEnv(
      {
        DB1_SUPABASE_URL: keys.NEXT_PUBLIC_SUPABASE_URL,
        DB1_SUPABASE_PUBLISHABLE_KEY: keys.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
      },
      { prefix: "DB1" },
    );

    expect(env.url).toBe(keys.NEXT_PUBLIC_SUPABASE_URL);
  });

  it("names the legacy variable when only it is set", () => {
    expect(() =>
      getEnv({
        NEXT_PUBLIC_SUPABASE_URL: keys.NEXT_PUBLIC_SUPABASE_URL,
        NEXT_PUBLIC_SUPABASE_ANON_KEY: "eyJ",
      }),
    ).toThrow(/NEXT_PUBLIC_SUPABASE_ANON_KEY is the legacy name/);
  });

  it("names the legacy secret when a secret key is required", () => {
    expect(() =>
      getEnv(
        { ...keys, SUPABASE_SERVICE_ROLE_KEY: "eyJ" },
        { require: ["secretKey"] },
      ),
    ).toThrow(/SUPABASE_SERVICE_ROLE_KEY is the legacy name/);
  });
});
