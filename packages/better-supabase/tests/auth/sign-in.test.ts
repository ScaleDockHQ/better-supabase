import { AuthApiError, AuthRetryableFetchError } from "@supabase/supabase-js";
import { describe, expect, it } from "vitest";

import {
  authFailure,
  isStandInUser,
  needsMfa,
  safeRedirectPath,
} from "../../src/auth/sign-in.ts";

describe("safeRedirectPath", () => {
  it.each([
    ["/dashboard?tab=1", "/dashboard?tab=1"],
    ["//evil.test", "/"],
    ["/\\evil.test", "/"],
    ["https://evil.test", "/"],
    ["/\tjavascript:alert(1)", "/"],
    ["", "/"],
    [null, "/"],
    [undefined, "/"],
  ])("maps %j to %j", (next, expected) => {
    expect(safeRedirectPath(next, "/")).toBe(expected);
  });
});

describe("authFailure", () => {
  it("keeps Auth's code and drops its message", () => {
    expect(
      authFailure(
        new AuthApiError(
          "Invalid login credentials",
          400,
          "invalid_credentials",
        ),
        "Sign-in",
        false,
      ),
    ).toMatchObject({
      kind: "unauthorized",
      message: "Sign-in failed",
      code: "invalid_credentials",
    });
  });

  it("maps 429 to rate_limited, 5xx and fetch failures to network, and a timeout to timeout", () => {
    expect(
      authFailure(new AuthApiError("slow", 429, undefined), "Sign-in", false),
    ).toMatchObject({ kind: "rate_limited" });
    expect(
      authFailure(new AuthApiError("down", 500, undefined), "Sign-in", false),
    ).toMatchObject({ kind: "network" });
    expect(
      authFailure(new AuthRetryableFetchError("offline", 0), "Sign-in", false),
    ).toMatchObject({ kind: "network", message: "offline" });
    expect(
      authFailure(new AuthRetryableFetchError("aborted", 0), "Sign-in", true),
    ).toMatchObject({ kind: "timeout" });
  });
});

describe("isStandInUser", () => {
  it("is true for a user without identities", () => {
    expect(isStandInUser({ id: "u", identities: [] })).toBe(true);
    expect(isStandInUser({ id: "u", identities: [{ id: "i" }] })).toBe(false);
    expect(isStandInUser(null)).toBe(false);
  });
});

describe("needsMfa", () => {
  it("is true only with a verified factor", () => {
    const user = (factors: unknown) => ({ id: "u", factors });

    expect(needsMfa(user([{ status: "verified" }]))).toBe(true);
    expect(needsMfa(user([{ status: "unverified" }]))).toBe(false);
    expect(needsMfa(user(undefined))).toBe(false);
    expect(needsMfa(undefined)).toBe(false);
  });
});
