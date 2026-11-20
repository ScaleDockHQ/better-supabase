import { describe, expect, it } from "vitest";

import { errorText } from "../../src/core/error-text.ts";

describe("errorText", () => {
  it("reads the message of an error, an object or any other value", () => {
    expect(errorText(new Error("boom"))).toBe("boom");
    expect(errorText({ message: "plain" })).toBe("plain");
    expect(errorText(42)).toBe("42");
  });
});
