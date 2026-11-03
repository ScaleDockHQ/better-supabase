import { describe, expect, it } from "vitest";

import {
  applySpecPatch,
  collapseSpecParts,
  parseSpecDocument,
  specDocumentContent,
  specDataSchemas,
  specOfMessage,
  validateSpec,
} from "../../src/json-render/index.ts";

const part = (data: unknown) => ({ type: "data-spec", data });

const message = {
  id: "m1",
  role: "assistant",
  parts: [
    { type: "text", text: "Here is the form" },
    part({ type: "patch", patch: { op: "add", path: "/root", value: "card" } }),
    part({
      type: "patch",
      patch: {
        op: "add",
        path: "/elements/card",
        value: { type: "Card", children: ["name"] },
      },
    }),
    { type: "text", text: "and a note" },
    part({
      type: "patch",
      patch: {
        op: "add",
        path: "/elements/name",
        value: { type: "Input", props: { label: "Name" } },
      },
    }),
  ],
};

describe("collapseSpecParts", () => {
  it("folds patches into one flat part at the first patch", () => {
    const collapsed = collapseSpecParts(message);

    expect(collapsed.parts).toHaveLength(3);
    expect(collapsed.parts[1]).toEqual({
      type: "data-spec",
      data: {
        type: "flat",
        spec: {
          root: "card",
          elements: {
            card: { type: "Card", children: ["name"] },
            name: { type: "Input", props: { label: "Name" } },
          },
        },
      },
    });
    expect(specOfMessage(message)?.root).toBe("card");
  });

  it("returns a message without spec parts unchanged", () => {
    const plain = { parts: [{ type: "text", text: "hi" }] };

    expect(collapseSpecParts(plain)).toBe(plain);
  });
});

describe("applySpecPatch", () => {
  it("replaces and removes, and refuses prototype keys", () => {
    const spec = {
      root: "a",
      elements: { a: { type: "Box", props: { n: 1 } } },
    };

    const replaced = applySpecPatch(spec, {
      op: "replace",
      path: "/elements/a/props/n",
      value: 2,
    });

    expect(replaced).toEqual({
      root: "a",
      elements: { a: { type: "Box", props: { n: 2 } } },
    });
    expect(spec.elements.a.props.n).toBe(1);

    expect(
      applySpecPatch(spec, { op: "remove", path: "/elements/a/props" }),
    ).toEqual({ root: "a", elements: { a: { type: "Box" } } });

    expect(() =>
      applySpecPatch(spec, { op: "add", path: "/__proto__/x", value: 1 }),
    ).toThrow(/patch path/);
  });
});

describe("specDataSchemas", () => {
  const validate = (value: unknown) =>
    specDataSchemas.spec["~standard"].validate(value);

  it("accepts the three part shapes and rejects others", () => {
    expect(
      validate({ type: "flat", spec: { root: "a", elements: {} } }),
    ).not.toHaveProperty("issues");
    expect(
      validate({ type: "patch", patch: { op: "nope", path: "/" } }),
    ).toHaveProperty("issues");
    expect(validate("x")).toHaveProperty("issues");
  });
});

describe("validateSpec", () => {
  it("reports a missing root, missing children and orphans", () => {
    const result = validateSpec(undefined, {
      root: "a",
      elements: { a: { type: "Box", children: ["b"] }, c: { type: "Box" } },
    });

    expect(result.ok).toBe(false);
    expect(!result.ok && result.issues.map((issue) => issue.code)).toEqual([
      "missing_child",
      "orphaned_element",
    ]);
  });

  it("runs the catalog", () => {
    const spec = { root: "a", elements: { a: { type: "Box" } } };

    expect(validateSpec({ validate: () => ({ success: true }) }, spec).ok).toBe(
      true,
    );
    expect(
      validateSpec({ validate: () => ({ success: false }) }, spec).ok,
    ).toBe(false);
  });
});

describe("spec documents", () => {
  it("round-trips a spec through the document content", () => {
    const spec = { root: "a", elements: { a: { type: "Box" } } };

    expect(parseSpecDocument(specDocumentContent(spec))).toEqual(spec);
    expect(parseSpecDocument("nope")).toBeUndefined();
  });
});
