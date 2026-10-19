import { describe, expect, it } from "vitest";

import {
  isSecretKey,
  REDACTED,
  redact,
  redactText,
  redactUrl,
} from "../../../src/cli/core/redact.ts";

describe("redact", () => {
  it("replaces strings under secret-looking keys", () => {
    expect(
      redact({
        source: { accessToken: "sbp_secret", projectRef: "abcd" },
        webhooks: [{ signingSecret: "whsec_x", url: "https://example.com" }],
        stripe: { apiKey: "sk_live", api_key: "sk_live" },
      }),
    ).toStrictEqual({
      source: { accessToken: REDACTED, projectRef: "abcd" },
      webhooks: [{ signingSecret: REDACTED, url: "https://example.com" }],
      stripe: { apiKey: REDACTED, api_key: REDACTED },
    });
  });

  it("keeps empty values, non-strings and keys that only contain a secret word", () => {
    expect(
      redact({ accessToken: "", tokenHook: "custom_access_token", keys: {} }),
    ).toStrictEqual({
      accessToken: "",
      tokenHook: "custom_access_token",
      keys: {},
    });
  });

  it("removes the password from URLs anywhere", () => {
    expect(
      redact({
        nested: ["postgresql://postgres:hunter2@db.example.com/postgres"],
      }),
    ).toStrictEqual({
      nested: ["postgresql://postgres:redacted@db.example.com/postgres"],
    });
    expect(redactUrl("not a url")).toBe(REDACTED);
    expect(redactUrl("postgresql://localhost/postgres")).toBe(
      "postgresql://localhost/postgres",
    );
  });

  it("passes functions and class instances through", () => {
    const generate = (): string[] => [];
    const at = new Date(0);

    expect(redact({ generate, at })).toStrictEqual({ generate, at });
  });

  it("matches secret keys by suffix", () => {
    expect(isSecretKey("serviceRoleSecret")).toBe(true);
    expect(isSecretKey("password")).toBe(true);
    expect(isSecretKey("tokens")).toBe(false);
    expect(isSecretKey("primaryKey")).toBe(false);
  });

  it("removes known secrets from text", () => {
    expect(
      redactText("Bearer sbp_0123456789 failed", ["sbp_0123456789", "short"]),
    ).toBe(`Bearer ${REDACTED} failed`);
  });
});
