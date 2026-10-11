import { describe, expect, it } from "vitest";

import { commentMeta } from "../../../src/cli/gen/comment.ts";
import { parseComment } from "../../../src/generators/shared.ts";

describe("commentMeta", () => {
  it("reads nothing from a missing or empty comment", () => {
    expect(commentMeta(null)).toEqual({});
    expect(commentMeta(undefined)).toEqual({});
    expect(commentMeta("")).toEqual({});
  });

  it("keeps the description without @example lines", () => {
    expect(commentMeta('Trading name.\n@example "Acme B.V."')).toEqual({
      description: "Trading name.",
    });
  });

  it("maps a @deprecated line, with or without text, and drops it", () => {
    expect(commentMeta("Old name.\n@deprecated")).toEqual({
      description: "Old name.",
      deprecated: true,
    });
    expect(
      commentMeta("Old name.\n@deprecated use display_name\n@example 1"),
    ).toEqual({ description: "Old name.", deprecated: true });
    expect(commentMeta("@deprecated")).toEqual({ deprecated: true });
  });

  it("leaves @deprecated inside a sentence alone", () => {
    expect(commentMeta("Replaces the @deprecated kvk column.")).toEqual({
      description: "Replaces the @deprecated kvk column.",
    });
  });

  it("agrees with the library's parseComment", () => {
    for (const comment of [
      "Trading name.\n@example 42",
      'Old.\n@deprecated soon\n@example "x"',
      "@deprecated",
    ]) {
      const { description, deprecated } = parseComment(comment);
      expect(commentMeta(comment)).toEqual({
        ...(description === undefined ? {} : { description }),
        ...(deprecated ? { deprecated } : {}),
      });
    }
  });
});
