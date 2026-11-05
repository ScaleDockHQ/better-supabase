import { describe, expect, expectTypeOf, it } from "vitest";

import type { AuthErrorKind } from "../../src/auth/index.ts";

import * as entry from "../../src/auth/index.ts";
import { authErrorKind } from "../../src/auth/index.ts";

describe("better-supabase/auth", () => {
  it("exports only authErrorKind as a value", () => {
    expect(Object.keys(entry)).toEqual(["authErrorKind"]);
  });

  it("classifies an auth-js error", () => {
    expect(authErrorKind({ code: "over_request_rate_limit" })).toBe(
      "rate-limited",
    );
  });

  it("types the result as AuthErrorKind", () => {
    expectTypeOf(authErrorKind).returns.toEqualTypeOf<AuthErrorKind>();
    expectTypeOf<AuthErrorKind>().toEqualTypeOf<
      | "retryable"
      | "session-missing"
      | "invalid-credentials"
      | "rate-limited"
      | "banned"
      | "unknown"
    >();
  });
});
