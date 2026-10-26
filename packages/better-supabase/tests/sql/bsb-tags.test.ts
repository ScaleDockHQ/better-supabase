import { describe, expect, it } from "vitest";

import {
  commentOnTableSql,
  formatBsbComment,
  parseBsbComment,
  setBsbTag,
} from "../../src/sql/bsb-tags.ts";

describe("parseBsbComment", () => {
  it("reads free text and tags", () => {
    expect(
      parseBsbComment("Invoices. @bsb subject title=number; realtime; audit"),
    ).toEqual({
      text: "Invoices.",
      tags: [
        { name: "subject", args: { title: "number" } },
        { name: "realtime", args: {} },
        { name: "audit", args: {} },
      ],
    });
  });

  it("treats a comment without a marker as text", () => {
    expect(parseBsbComment("Plain @bsbx note")).toEqual({
      text: "Plain @bsbx note",
      tags: [],
    });
    expect(parseBsbComment(null)).toEqual({ text: "", tags: [] });
  });

  it("reads quoted values and bare flags", () => {
    expect(parseBsbComment('@bsb subject title="a b; c" soft')).toEqual({
      text: "",
      tags: [{ name: "subject", args: { title: "a b; c", soft: true } }],
    });
  });
});

describe("formatBsbComment", () => {
  it("round-trips", () => {
    const text = "Invoices. @bsb subject title=number; realtime";

    expect(formatBsbComment(parseBsbComment(text))).toBe(text);
  });
});

describe("setBsbTag", () => {
  it("adds, replaces and removes a tag and keeps the text", () => {
    const added = setBsbTag("Notes", "realtime", {
      name: "realtime",
      args: {},
    });

    expect(added).toBe("Notes @bsb realtime");

    const replaced = setBsbTag(added, "realtime", {
      name: "realtime",
      args: { only: "insert" },
    });

    expect(replaced).toBe("Notes @bsb realtime only=insert");
    expect(setBsbTag(replaced, "realtime", undefined)).toBe("Notes");
  });
});

describe("commentOnTableSql", () => {
  it("escapes quotes", () => {
    expect(commentOnTableSql("public.notes", "It's @bsb audit")).toBe(
      "comment on table public.notes is 'It''s @bsb audit';",
    );
  });
});
