import { describe, expect, it } from "vitest";

import { authErrorKind } from "../../src/auth/error-kind.ts";

describe("authErrorKind", () => {
  it("reads the code first", () => {
    expect(authErrorKind({ code: "invalid_credentials", status: 400 })).toBe(
      "invalid-credentials",
    );
    expect(authErrorKind({ code: "refresh_token_not_found" })).toBe(
      "session-missing",
    );
    expect(authErrorKind({ code: "user_banned" })).toBe("banned");
  });

  it("uses the status and name next", () => {
    expect(authErrorKind({ status: 429 })).toBe("rate-limited");
    expect(authErrorKind({ status: 503 })).toBe("retryable");
    expect(authErrorKind({ name: "AuthRetryableFetchError" })).toBe(
      "retryable",
    );
  });

  it("falls back to the message, then to unknown", () => {
    expect(authErrorKind({ message: "Invalid login credentials" })).toBe(
      "invalid-credentials",
    );
    expect(authErrorKind({ message: "weird" })).toBe("unknown");
    expect(authErrorKind(null)).toBe("unknown");
  });
});
