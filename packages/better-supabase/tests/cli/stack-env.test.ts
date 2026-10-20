import { describe, expect, it } from "vitest";

import {
  jwksUrlOf,
  prefixFromFlag,
  redactValue,
  stackEnvValues,
  staleVariables,
} from "../../src/cli/stack-env.ts";

const STATUS = {
  API_URL: "http://127.0.0.1:55021",
  PUBLISHABLE_KEY: "sb_publishable_abc",
  SECRET_KEY: "sb_secret_xyz",
  DB_URL: "postgresql://postgres:postgres@127.0.0.1:55022/postgres",
  JWT_SECRET: "super-secret-jwt-token",
};

describe("prefixFromFlag", () => {
  it("maps framework names and keeps literal prefixes", () => {
    expect(prefixFromFlag("next")).toBe("NEXT_PUBLIC_");
    expect(prefixFromFlag("Vite")).toBe("VITE_");
    expect(prefixFromFlag("expo")).toBe("EXPO_PUBLIC_");
    expect(prefixFromFlag("sveltekit")).toBe("PUBLIC_");
    expect(prefixFromFlag("none")).toBe("");
    expect(prefixFromFlag("MY_")).toBe("MY_");
  });
});

describe("stackEnvValues", () => {
  it("writes the server keys plain and only the URL and publishable key prefixed", () => {
    expect(stackEnvValues(STATUS, "NEXT_PUBLIC_")).toEqual({
      SUPABASE_URL: "http://127.0.0.1:55021",
      SUPABASE_PUBLISHABLE_KEY: "sb_publishable_abc",
      SUPABASE_SECRET_KEY: "sb_secret_xyz",
      SUPABASE_JWKS_URL: "http://127.0.0.1:55021/auth/v1/.well-known/jwks.json",
      SUPABASE_DB_URL: STATUS.DB_URL,
      SUPABASE_JWT_SECRET: STATUS.JWT_SECRET,
      NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:55021",
      NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_abc",
    });
  });

  it("never gives the secret key a browser prefix", () => {
    const values = stackEnvValues(STATUS, "NEXT_PUBLIC_") ?? {};

    expect(Object.keys(values).filter((key) => key.includes("SECRET"))).toEqual(
      ["SUPABASE_SECRET_KEY", "SUPABASE_JWT_SECRET"],
    );
  });

  it("falls back to the legacy keys and needs a URL and a publishable key", () => {
    expect(
      stackEnvValues(
        { API_URL: "http://x:1", ANON_KEY: "anon", SERVICE_ROLE_KEY: "svc" },
        "",
      ),
    ).toMatchObject({
      SUPABASE_PUBLISHABLE_KEY: "anon",
      SUPABASE_SECRET_KEY: "svc",
    });
    expect(stackEnvValues({ API_URL: "http://x:1" }, "")).toBeUndefined();
  });

  it("builds the JWKS URL without a double slash", () => {
    expect(jwksUrlOf("http://x:1/")).toBe(
      "http://x:1/auth/v1/.well-known/jwks.json",
    );
  });
});

describe("redactValue", () => {
  it("shows a URL's host and port and a database URL's name, never a password", () => {
    expect(redactValue("http://127.0.0.1:54321")).toBe("127.0.0.1:54321");
    expect(redactValue(STATUS.DB_URL)).toBe("127.0.0.1:55022/postgres");
    expect(redactValue(STATUS.DB_URL)).not.toContain("postgres:postgres");
  });

  it("fingerprints keys", () => {
    const redacted = redactValue("sb_secret_xyz");

    expect(redacted).toMatch(/^sha256:[0-9a-f]{8}$/);
    expect(redacted).not.toContain("xyz");
  });
});

describe("staleVariables", () => {
  const values = stackEnvValues(STATUS, "") ?? {};

  it("names each exported variable that differs, with both values redacted", () => {
    expect(
      staleVariables(
        {
          SUPABASE_URL: "http://127.0.0.1:54321",
          SUPABASE_SECRET_KEY: "sb_secret_old",
          SUPABASE_PUBLISHABLE_KEY: "sb_publishable_abc",
          SUPABASE_JWKS_URL: "",
        },
        values,
      ),
    ).toEqual([
      {
        variable: "SUPABASE_URL",
        shell: "127.0.0.1:54321",
        stack: "127.0.0.1:55021",
        message:
          "SUPABASE_URL is exported as 127.0.0.1:54321, but the running stack has 127.0.0.1:55021.",
      },
      expect.objectContaining({
        variable: "SUPABASE_SECRET_KEY",
        shell: expect.stringMatching(/^sha256:/),
        stack: expect.stringMatching(/^sha256:/),
      }),
    ]);
  });

  it("reports nothing when the shell matches or exports nothing", () => {
    expect(staleVariables({}, values)).toEqual([]);
    expect(staleVariables({ ...values }, values)).toEqual([]);
  });
});
