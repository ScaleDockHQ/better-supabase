import {
  decodePreset,
  namedPreset,
  type Preset,
  resolvePreset,
} from "better-supabase/preset";
import { describe, expect, test } from "vitest";

import { blocks } from "../../lib/blocks";
import {
  applyNamedPreset,
  blockGroups,
  createHref,
  DEFAULT_PRESET,
  graphLayout,
  initialPreset,
  matchingPreset,
  NODE_WIDTH,
  rowNote,
  toggleBlock,
} from "../../lib/create";

const minimal = namedPreset("minimal");

function rowOf(preset: Preset, name: string) {
  return blockGroups(preset, resolvePreset(preset))
    .flatMap((group) => group.rows)
    .find((row) => row.name === name);
}

describe("the /create URL", () => {
  test("starts from a name, a code or the default", () => {
    expect(initialPreset(null)).toEqual(namedPreset(DEFAULT_PRESET));
    expect(initialPreset("")).toEqual(namedPreset(DEFAULT_PRESET));
    expect(initialPreset("minimal")).toEqual(minimal);
    expect(initialPreset("not a preset")).toEqual(namedPreset(DEFAULT_PRESET));
    const code = createHref(minimal).split("=")[1] ?? "";
    expect(initialPreset(code)).toEqual(minimal);
  });

  test("keeps the selection as a code that decodes to it", () => {
    const preset = toggleBlock(minimal, "comments");
    const code = createHref(preset).replace("/create?preset=", "");
    expect(decodePreset(code).preset.blocks.toSorted()).toEqual([
      "comments",
      "profiles",
    ]);
  });
});

describe("selection helpers", () => {
  test("toggle a block on and off", () => {
    const on = toggleBlock(minimal, "tags");
    expect(on.blocks).toEqual(["profiles", "tags"]);
    expect(toggleBlock(on, "tags").blocks).toEqual(["profiles"]);
  });

  test("name the preset a selection matches", () => {
    expect(matchingPreset(minimal)).toBe("minimal");
    expect(matchingPreset(toggleBlock(minimal, "tags"))).toBeUndefined();
    const crm = applyNamedPreset({ ...minimal, casing: "camel" }, "crm");
    expect(matchingPreset(crm)).toBe("crm");
    expect(crm.casing).toBe("camel");
  });
});

describe("blockGroups", () => {
  test("lists every catalog block once, in the /blocks categories", () => {
    const names = blockGroups(minimal, resolvePreset(minimal)).flatMap(
      (group) => group.rows.map((row) => row.name),
    );
    expect(names.toSorted()).toEqual(
      blocks.map((block) => block.name).toSorted(),
    );
  });

  test("switches on what a selected block requires, with the reason", () => {
    const preset = toggleBlock(minimal, "comments");
    expect(rowOf(preset, "comments")?.state).toEqual({ kind: "selected" });
    const tenant = rowOf(preset, "tenant");
    expect(tenant?.state).toEqual({
      kind: "required",
      by: ["access", "comments"],
    });
    expect(
      rowNote(rowOf(preset, "access")?.state ?? { kind: "selected" }),
    ).toBe("Required by comments");
  });

  test("disables a block that can't install, with the reason", () => {
    const preset: Preset = { ...minimal, scope: "user" };
    const state = rowOf(preset, "organizations")?.state;
    expect(state).toEqual({
      kind: "conflict",
      reason: 'it needs tenants, and scope "user" has none',
    });
    expect(rowNote(state ?? { kind: "selected" })).toBe(
      'Unavailable: it needs tenants, and scope "user" has none',
    );
  });

  test("says which installed blocks an available block works with", () => {
    const preset = toggleBlock(minimal, "comments");
    const state = rowOf(preset, "notifications")?.state;
    expect(state?.kind).toBe("available");
    expect(rowNote(state ?? { kind: "selected" })).toContain("comments");
    expect(rowNote({ kind: "available", worksWith: [] })).toBeUndefined();
    expect(rowNote({ kind: "selected" })).toBeUndefined();
  });
});

describe("graphLayout", () => {
  test("puts every block right of what it requires", () => {
    const layout = graphLayout(resolvePreset(toggleBlock(minimal, "comments")));
    const x = new Map(layout.nodes.map((node) => [node.name, node.x]));
    for (const edge of layout.edges.filter(
      (each) => each.kind === "requires",
    )) {
      expect(x.get(edge.from)).toBeGreaterThan(x.get(edge.to) ?? Infinity);
    }
    expect(layout.edges).toContainEqual({
      from: "comments",
      to: "access",
      kind: "requires",
    });
    expect(layout.width).toBeGreaterThan(NODE_WIDTH * 3);
    expect(
      layout.nodes.find((node) => node.name === "comments")?.selected,
    ).toBe(true);
  });

  test("is empty without blocks", () => {
    const layout = graphLayout(resolvePreset({ ...minimal, blocks: [] }));
    expect(layout.nodes).toEqual([]);
    expect(layout.width).toBe(16);
  });
});
