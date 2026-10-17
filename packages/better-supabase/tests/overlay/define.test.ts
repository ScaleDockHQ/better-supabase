import { describe, expect, expectTypeOf, it } from "vitest";

import type {
  Overlay,
  Overlay10,
  Overlay11,
  Overlay12,
} from "../../src/overlay/index.ts";

import {
  defineOverlay,
  expandReusableActions,
} from "../../src/overlay/index.ts";

const info = { title: "Public API", version: "1.0.0" };

describe("defineOverlay", () => {
  it("defaults to 1.1.0 and puts the version first", () => {
    const overlay = defineOverlay({
      info,
      actions: [{ target: "$.info", copy: "$.paths['/a']" }],
    });

    expectTypeOf(overlay).toEqualTypeOf<Overlay11>();
    expect(overlay.overlay).toBe("1.1.0");
    expect(Object.keys(overlay)[0]).toBe("overlay");
  });

  it("picks 1.2.0 when the input uses a 1.2 feature", () => {
    const withRef = defineOverlay({
      info,
      components: { actions: { a: { fields: { remove: true } } } },
      actions: [{ $ref: "#/components/actions/a", target: "$.x" }],
    });

    expectTypeOf(withRef).toEqualTypeOf<Overlay12>();
    expect(withRef.overlay).toBe("1.2.0");

    const withSelf = defineOverlay({
      info,
      $self: "https://example.com/o.yaml",
      actions: [{ target: "$.x", remove: true }],
    });

    expectTypeOf(withSelf).toEqualTypeOf<Overlay12>();
    expect(withSelf.overlay).toBe("1.2.0");
  });

  it("keeps an explicit version", () => {
    const v10 = defineOverlay({
      overlay: "1.0.0",
      info,
      extends: "https://example.com/openapi.json",
      actions: [{ target: "$.x", update: { a: 1 } }],
      "x-owner": "platform",
    });

    expectTypeOf(v10).toEqualTypeOf<Overlay10>();
    expect(v10).toEqual({
      overlay: "1.0.0",
      info,
      extends: "https://example.com/openapi.json",
      actions: [{ target: "$.x", update: { a: 1 } }],
      "x-owner": "platform",
    });

    const v12 = defineOverlay({
      overlay: "1.2.0",
      info,
      actions: [{ target: "$.x", remove: true }],
    });

    expectTypeOf(v12).toEqualTypeOf<Overlay12>();

    const v11 = defineOverlay({
      overlay: "1.1.0",
      info,
      actions: [{ target: "$.x", remove: true }],
    });

    expectTypeOf(v11).toEqualTypeOf<Overlay11>();
  });

  it("throws for inputs a schema would accept but tools cannot apply", () => {
    expect(() => defineOverlay({ info, actions: [] })).toThrow(
      "at least one action",
    );
    expect(() =>
      defineOverlay({
        overlay: "1.1.0",
        info,
        $self: "https://example.com/o.yaml",
        actions: [{ target: "$", remove: true }],
      }),
    ).toThrow("need overlay 1.2.0, not 1.1.0");
    expect(() =>
      defineOverlay({
        overlay: "1.0.0",
        info,
        actions: [{ target: "$", copy: "$.a" }],
      }),
    ).toThrow("copy needs overlay 1.1.0");
    expect(() =>
      defineOverlay({
        info,
        extends: "https://example.com/openapi.json#/paths",
        actions: [{ target: "$", remove: true }],
      }),
    ).toThrow("extends must not contain a fragment");
    expect(() =>
      defineOverlay({
        info,
        actions: [{ $ref: "#/components/actions/missing", target: "$" }],
      }),
    ).toThrow("does not exist in components.actions");
  });

  it("throws for an unknown version at runtime", () => {
    // SAFETY: an untyped caller passes an unknown version.
    const input = {
      overlay: "9.9.9",
      info,
      actions: [{ target: "$", remove: true }],
    } as unknown as Parameters<typeof defineOverlay>[0];

    expect(() => defineOverlay(input)).toThrow("unsupported overlay 9.9.9");
  });
});

describe("expandReusableActions", () => {
  it("turns a 1.2 overlay into an equivalent 1.1 overlay", () => {
    const overlay = defineOverlay({
      info,
      $self: "https://example.com/o.yaml",
      extends: "https://example.com/openapi.json",
      "x-owner": "platform",
      components: {
        actions: {
          "a/b": { fields: { update: { "x-a": 1 }, description: "shared" } },
        },
      },
      actions: [
        { target: "$.info", remove: true },
        {
          $ref: "#/components/actions/a~1b",
          target: "$.paths.*",
          description: "mine",
        },
      ],
    });

    const { overlay: expanded, diagnostics } = expandReusableActions(overlay);
    expect(diagnostics).toEqual([]);
    expect(expanded).toEqual({
      overlay: "1.1.0",
      info,
      extends: "https://example.com/openapi.json",
      actions: [
        { target: "$.info", remove: true },
        { update: { "x-a": 1 }, description: "mine", target: "$.paths.*" },
      ],
      "x-owner": "platform",
    });
  });

  it("leaves out references that do not resolve and malformed entries", () => {
    const overlay = {
      overlay: "1.2.0",
      info,
      actions: [
        { $ref: "#/components/actions/missing", target: "$" },
        "nope",
        { target: "$", remove: true },
      ],
    };

    // SAFETY: a malformed overlay on purpose.
    const malformed = overlay as unknown as Overlay;
    const result = expandReusableActions(malformed);
    expect(result.overlay.actions).toEqual([{ target: "$", remove: true }]);
    expect(result.diagnostics.map((d) => [d.code, d.pointer])).toEqual([
      ["overlay-ref-unresolved", "/actions/0"],
    ]);
  });
});
