import { describe, expect, it } from "vitest";

import {
  BLOCK_HINT_MESSAGES,
  blockErrorMessage,
  fieldMessages,
  hintMessage,
} from "../../../src/blocks/messages/index.ts";
import { dbError, invalidInput } from "../../../src/core/errors.ts";

describe("BLOCK_HINT_MESSAGES", () => {
  it("words every code as a sentence", () => {
    const messages = Object.entries(BLOCK_HINT_MESSAGES);

    expect(messages.length).toBeGreaterThan(1000);

    for (const [code, message] of messages) {
      expect(code).toMatch(/^[A-Z][A-Z0-9_]*$/);
      expect(message).toMatch(/[.!?]$/);
      expect(message).not.toContain("%");
    }
  });

  it("uses the message the SQL raises a code with", () => {
    expect(BLOCK_HINT_MESSAGES.ACCESS_NOT_GRANTED).toBe(
      "This access isn't active.",
    );
  });
});

describe("hintMessage", () => {
  it("returns the default, a translation, or nothing for an unknown code", () => {
    expect(hintMessage("TAG_NOT_FOUND")).toBe(
      BLOCK_HINT_MESSAGES.TAG_NOT_FOUND,
    );
    expect(hintMessage("TAG_NOT_FOUND", (code) => `nl:${code}`)).toBe(
      "nl:TAG_NOT_FOUND",
    );
    expect(hintMessage("TAG_NOT_FOUND", () => undefined)).toBe(
      BLOCK_HINT_MESSAGES.TAG_NOT_FOUND,
    );
    expect(hintMessage("NOT_A_CODE")).toBeUndefined();
    expect(hintMessage("toString")).toBeUndefined();
  });
});

describe("blockErrorMessage", () => {
  it("reads the hint of the error", () => {
    expect(
      blockErrorMessage(dbError("raised", "x", { hint: "TAG_NOT_FOUND" })),
    ).toBe(BLOCK_HINT_MESSAGES.TAG_NOT_FOUND);
    expect(blockErrorMessage(dbError("raised", "x"))).toBeUndefined();
    expect(
      blockErrorMessage(dbError("raised", "x", { hint: "OTHER" })),
    ).toBeUndefined();
  });
});

describe("fieldMessages", () => {
  const error = invalidInput("Check the lines", [
    { path: ["lines", 0, "quantity"], code: "QTY_LOW", message: "Too few." },
    { path: ["lines", 0, "quantity"], code: "QTY_ODD", message: "Odd." },
    { path: ["name"], code: "NAME_REQUIRED", message: "Name it." },
  ]);

  it("keys the first message by the dotted path", () => {
    expect(fieldMessages(error)).toEqual({
      "lines.0.quantity": "Too few.",
      name: "Name it.",
    });
  });

  it("translates by field code", () => {
    expect(
      fieldMessages(error, (code) =>
        code === "NAME_REQUIRED" ? "Geef een naam." : undefined,
      )["name"],
    ).toBe("Geef een naam.");
  });

  it("is empty for other errors", () => {
    expect(fieldMessages(dbError("not_found", "x"))).toEqual({});
    expect(fieldMessages(dbError("invalid_input", "x"))).toEqual({});
  });
});
