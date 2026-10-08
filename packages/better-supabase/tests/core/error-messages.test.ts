import { describe, expect, expectTypeOf, it } from "vitest";

import {
  createErrorMessages,
  type ErrorMessages,
} from "../../src/core/error-messages.ts";
import { dbError } from "../../src/core/errors.ts";

const messages: ErrorMessages = {
  not_found: "Gone",
  unauthorized: "Sign in",
  forbidden: (error) =>
    error.required === "aal2" ? "Verify your second factor" : "Not allowed",
  conflict: "Exists",
  foreign_key: "In use",
  check: "Invalid",
  not_null: (error) => `${error.column ?? "A field"} is required`,
  exclusion: "Overlaps",
  invalid_input: "Invalid",
  invalid_value: "Invalid",
  raised: (error) => error.message,
  timeout: "Try again",
  serialization: "Try again",
  network: "Offline",
  aborted: "Cancelled",
  invalid_request: "Invalid",
  validation: (error) => `${error.issues.length} fields`,
  multiple_rows: "Exists",
  stale: "Reload",
  max_affected: "Too many rows",
  rate_limited: "Slow down",
  quota_exceeded: "Upgrade",
  unsupported: "Unsupported",
  unexpected: "Something went wrong",
};

describe("createErrorMessages", () => {
  it("returns the string or calls the formatter for the error's kind", () => {
    const message = createErrorMessages(messages);
    expect(message(dbError("not_found", "x"))).toBe("Gone");
    expect(message(dbError("raised", "Seat limit reached"))).toBe(
      "Seat limit reached",
    );
    expect(message(dbError("forbidden", "x", { required: "aal2" }))).toBe(
      "Verify your second factor",
    );
    expect(
      message(dbError("validation", "x", { issues: [{ message: "a" }] })),
    ).toBe("1 fields");
  });

  it("requires every kind", () => {
    const { unexpected: _unexpected, ...missing } = messages;
    expectTypeOf(missing).not.toExtend<ErrorMessages>();
  });
});
