import { describe, expect, it } from "vitest";

import {
  applySpecPatch,
  collapseSpecParts,
  isSpec,
  parseSpecDocument,
  specDataSchemas,
  specOfMessage,
  validateSpec,
} from "../../src/json-render/index.ts";

const validate = (value: unknown) =>
  specDataSchemas.spec["~standard"].validate(value);

describe("specDataSchemas", () => {
  it("accepts each part type", () => {
    const spec = { root: "a", elements: { a: { type: "Box" } } };

    expect(validate({ type: "flat", spec })).toEqual({
      value: { type: "flat", spec },
    });
    expect(validate({ type: "nested", spec: { a: 1 } })).toMatchObject({
      value: { type: "nested" },
    });
    expect(
      validate({
        type: "patch",
        patch: { op: "test", path: "/root", value: "a" },
      }),
    ).toMatchObject({ value: { type: "patch" } });
  });

  it("names what is wrong with a part", () => {
    const messages = [
      "text",
      { type: "patch", patch: { op: "bogus", path: "/a" } },
      { type: "flat", spec: { root: 1 } },
      { type: "nested", spec: [] },
      { type: "other" },
    ].map((value) => validate(value));

    expect(
      messages.map((result) =>
        "issues" in result ? result.issues?.[0]?.message : "",
      ),
    ).toEqual([
      "a spec part must be an object",
      "a patch part needs an RFC 6902 operation",
      "a flat part needs a spec with root and elements",
      "a nested part needs a spec object",
      "the type must be patch, flat or nested",
    ]);
  });
});

describe("applySpecPatch operations", () => {
  const spec = {
    root: "a",
    elements: { a: { type: "Box", children: ["b", "c"] } },
  };

  it("replaces, removes and appends in arrays", () => {
    const replaced = applySpecPatch(spec, {
      op: "replace",
      path: "/elements/a/children/0",
      value: "z",
    });

    const appended = applySpecPatch(spec, {
      op: "add",
      path: "/elements/a/children/-",
      value: "d",
    });

    const removed = applySpecPatch(spec, {
      op: "remove",
      path: "/elements/a/children/0",
    });

    expect(replaced).toMatchObject({
      elements: { a: { children: ["z", "c"] } },
    });
    expect(appended).toMatchObject({
      elements: { a: { children: ["b", "c", "d"] } },
    });
    expect(removed).toMatchObject({ elements: { a: { children: ["c"] } } });
  });

  it("copies and moves a value, and leaves the input untouched", () => {
    const copied = applySpecPatch(spec, {
      op: "copy",
      from: "/elements/a",
      path: "/elements/b",
    });

    const moved = applySpecPatch(spec, {
      op: "move",
      from: "/elements/a",
      path: "/elements/b",
    });

    expect(Object.keys(copied["elements"] as object)).toEqual(["a", "b"]);
    expect(Object.keys(moved["elements"] as object)).toEqual(["b"]);
    expect(Object.keys(spec.elements)).toEqual(["a"]);
  });

  it("treats test as a no-op", () => {
    expect(
      applySpecPatch(spec, { op: "test", path: "/root", value: "a" }),
    ).toEqual(spec);
  });

  it("refuses a missing parent and an empty path", () => {
    expect(() =>
      applySpecPatch(spec, { op: "add", path: "/nope/x", value: 1 }),
    ).toThrow(/no object at/);
    expect(() =>
      applySpecPatch(spec, { op: "add", path: "", value: 1 }),
    ).toThrow(/must name a key/);
    expect(() =>
      applySpecPatch(spec, { op: "add", path: "/a/b", value: 1 }),
    ).toThrow(/no object at/);
  });

  it("reads escaped pointer segments", () => {
    const next = applySpecPatch(
      { root: "a", elements: {} },
      { op: "add", path: "/elements/a~1b~0c", value: { type: "X" } },
    );

    expect(Object.keys(next["elements"] as object)).toEqual(["a/b~c"]);
  });
});

describe("collapseSpecParts and specOfMessage", () => {
  const flat = {
    type: "data-spec",
    data: {
      type: "flat",
      spec: { root: "a", elements: { a: { type: "Box" } } },
    },
  };

  it("keeps a message with no spec parts as is", () => {
    const plain = { parts: [{ type: "text", text: "hi" }] };

    expect(collapseSpecParts(plain)).toBe(plain);
    expect(specOfMessage(plain)).toBeUndefined();
  });

  it("keeps a message whose patches never set a root", () => {
    const partial = {
      parts: [
        {
          type: "data-spec",
          data: { type: "patch", patch: { op: "remove", path: "/root" } },
        },
      ],
    };

    expect(collapseSpecParts(partial)).toBe(partial);
  });

  it("returns a flat spec and ignores malformed spec parts", () => {
    const message = {
      parts: [{ type: "data-spec", data: { type: "nope" } }, flat],
    };

    expect(specOfMessage(message)).toEqual(flat.data.spec);
  });

  it("starts from a nested part", () => {
    const message = {
      parts: [
        {
          type: "data-spec",
          data: {
            type: "nested",
            spec: { root: "a", elements: { a: { type: "Box" } } },
          },
        },
      ],
    };

    expect(specOfMessage(message)).toEqual(flat.data.spec);
  });
});

describe("validateSpec and documents", () => {
  const spec = {
    root: "a",
    elements: { a: { type: "Box", children: ["b"] }, b: { type: "Leaf" } },
  };

  it("rejects a value that is not a spec", () => {
    expect(validateSpec(undefined, { nope: true })).toMatchObject({
      ok: false,
      issues: [{ code: "invalid_spec" }],
    });
    expect(isSpec({ root: "a" })).toBe(false);
  });

  it("asks the catalog and reports its error", () => {
    const failing = {
      validate: () => ({ success: false, error: new Error("bad props") }),
    };

    const vague = { validate: () => ({ success: false }) };
    const fine = { validate: () => ({ success: true }) };

    expect(validateSpec(failing, spec)).toMatchObject({
      issues: [{ code: "catalog", message: "bad props" }],
    });
    expect(validateSpec(vague, spec)).toMatchObject({
      issues: [{ message: "the spec does not match the catalog" }],
    });
    expect(validateSpec(fine, spec)).toEqual({ ok: true, spec });
  });

  it("reports a missing root and a shared child only once", () => {
    const shared = {
      root: "a",
      elements: {
        a: { type: "Box", children: ["b", "b", "gone"] },
        b: { type: "Leaf" },
      },
    };

    expect(validateSpec(undefined, shared)).toMatchObject({
      issues: [{ code: "missing_child" }],
    });
    expect(
      validateSpec(undefined, { root: "x", elements: { a: { type: "Box" } } }),
    ).toMatchObject({
      issues: [{ code: "root_not_found" }, { code: "orphaned_element" }],
    });
  });

  it("reads a document back, or nothing", () => {
    expect(parseSpecDocument(JSON.stringify(spec))).toEqual(spec);
    expect(parseSpecDocument("{")).toBeUndefined();
    expect(parseSpecDocument("[]")).toBeUndefined();
  });
});
