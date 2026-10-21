import { describe, expect, it } from "vitest";

import {
  applyPatch,
  createPatch,
  JsonPatchError,
  type JsonPatchOperation,
  type JsonValue,
  jsonEqual,
} from "../../src/blocks/versions/index.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

interface Example {
  readonly name: string;
  readonly doc: JsonValue;
  readonly patch: readonly JsonPatchOperation[];
  readonly expected?: JsonValue;
}

/** RFC 6902 Appendix A, the examples that succeed. */
const APPENDIX_A: readonly Example[] = [
  {
    name: "A.1 adding an object member",
    doc: { foo: "bar" },
    patch: [{ op: "add", path: "/baz", value: "qux" }],
    expected: { baz: "qux", foo: "bar" },
  },
  {
    name: "A.2 adding an array element",
    doc: { foo: ["bar", "baz"] },
    patch: [{ op: "add", path: "/foo/1", value: "qux" }],
    expected: { foo: ["bar", "qux", "baz"] },
  },
  {
    name: "A.3 removing an object member",
    doc: { baz: "qux", foo: "bar" },
    patch: [{ op: "remove", path: "/baz" }],
    expected: { foo: "bar" },
  },
  {
    name: "A.4 removing an array element",
    doc: { foo: ["bar", "qux", "baz"] },
    patch: [{ op: "remove", path: "/foo/1" }],
    expected: { foo: ["bar", "baz"] },
  },
  {
    name: "A.5 replacing a value",
    doc: { baz: "qux", foo: "bar" },
    patch: [{ op: "replace", path: "/baz", value: "boo" }],
    expected: { baz: "boo", foo: "bar" },
  },
  {
    name: "A.6 moving a value",
    doc: { foo: { bar: "baz", waldo: "fred" }, qux: { corge: "grault" } },
    patch: [{ op: "move", from: "/foo/waldo", path: "/qux/thud" }],
    expected: { foo: { bar: "baz" }, qux: { corge: "grault", thud: "fred" } },
  },
  {
    name: "A.7 moving an array element",
    doc: { foo: ["all", "grass", "cows", "eat"] },
    patch: [{ op: "move", from: "/foo/1", path: "/foo/3" }],
    expected: { foo: ["all", "cows", "eat", "grass"] },
  },
  {
    name: "A.8 testing a value: success",
    doc: { baz: "qux", foo: ["a", 2, "c"] },
    patch: [
      { op: "test", path: "/baz", value: "qux" },
      { op: "test", path: "/foo/1", value: 2 },
    ],
    expected: { baz: "qux", foo: ["a", 2, "c"] },
  },
  {
    name: "A.10 adding a nested member object",
    doc: { foo: "bar" },
    patch: [{ op: "add", path: "/child", value: { grandchild: {} } }],
    expected: { foo: "bar", child: { grandchild: {} } },
  },
  {
    name: "A.14 ~ escape ordering",
    doc: { "/": 9, "~1": 10 },
    patch: [{ op: "test", path: "/~01", value: 10 }],
    expected: { "/": 9, "~1": 10 },
  },
  {
    name: "A.16 adding an array value",
    doc: { foo: ["bar"] },
    patch: [{ op: "add", path: "/foo/-", value: ["abc", "def"] }],
    expected: { foo: ["bar", ["abc", "def"]] },
  },
];

/** RFC 6902 Appendix A, the examples that are errors. */
const ERRORS: readonly Example[] = [
  {
    name: "A.9 testing a value: error",
    doc: { baz: "qux" },
    patch: [{ op: "test", path: "/baz", value: "bar" }],
  },
  {
    name: "A.12 adding to a nonexistent target",
    doc: { foo: "bar" },
    patch: [{ op: "add", path: "/baz/bat", value: "qux" }],
  },
  {
    name: "A.15 comparing strings and numbers",
    doc: { "/": 9, "~1": 10 },
    patch: [{ op: "test", path: "/~01", value: "10" }],
  },
];

describe("RFC 6902 JSON Patch", () => {
  it("pins the JSON Patch version", () => {
    expect(SPEC_PINS.rfc6902).toBe("2013-04");
  });

  it.each(APPENDIX_A.map((example) => [example.name, example] as const))(
    "%s",
    (_name, example) => {
      const before = structuredClone(example.doc);
      expect(applyPatch(example.doc, example.patch)).toEqual(example.expected);
      expect(example.doc).toEqual(before);
    },
  );

  it.each(ERRORS.map((example) => [example.name, example] as const))(
    "%s",
    (_name, example) => {
      expect(() => applyPatch(example.doc, example.patch)).toThrow(
        JsonPatchError,
      );
    },
  );

  it("ignores the order of an object's members when testing (A.11 and 4.6)", () => {
    expect(
      applyPatch({ a: { b: 1, c: [1, { d: null }] } }, [
        { op: "test", path: "/a", value: { c: [1, { d: null }], b: 1 } },
      ]),
    ).toEqual({ a: { b: 1, c: [1, { d: null }] } });
    expect(jsonEqual([1], [1, 2])).toBe(false);
    expect(jsonEqual({ a: 1 }, { b: 1 })).toBe(false);
    expect(jsonEqual({ a: 1 }, [1])).toBe(false);
    expect(jsonEqual("1", 1)).toBe(false);
  });

  it("copies, replaces the root and removes the root", () => {
    expect(
      applyPatch({ a: [1] }, [{ op: "copy", from: "/a", path: "/b" }]),
    ).toEqual({ a: [1], b: [1] });
    expect(applyPatch({ a: 1 }, [{ op: "replace", path: "", value: 2 }])).toBe(
      2,
    );
    expect(applyPatch({ a: 1 }, [{ op: "remove", path: "" }])).toBe(null);
  });

  it.each<readonly [string, JsonValue, JsonPatchOperation]>([
    ["a path without a leading slash", {}, { op: "remove", path: "a" }],
    ["an invalid escape", { a: 1 }, { op: "remove", path: "/~2" }],
    ["a leading zero", { a: [1, 2] }, { op: "remove", path: "/a/01" }],
    [
      "an index past the end",
      { a: [1] },
      { op: "add", path: "/a/2", value: 0 },
    ],
    ["removing past the end", { a: [1] }, { op: "remove", path: "/a/1" }],
    ["a missing member", { a: 1 }, { op: "remove", path: "/b" }],
    ["a scalar parent", { a: 1 }, { op: "add", path: "/a/b", value: 0 }],
    [
      "a move into a child",
      { a: { b: 1 } },
      { op: "move", from: "/a", path: "/a/b/c" },
    ],
    [
      "reading through a scalar",
      { a: 1 },
      { op: "test", path: "/a/b", value: 1 },
    ],
  ])("refuses %s", (_name, doc, operation) => {
    let caught: unknown;

    try {
      applyPatch(doc, [operation]);
    } catch (error) {
      caught = error;
    }

    expect(caught).toBeInstanceOf(JsonPatchError);
    expect((caught as JsonPatchError).index).toBe(0);
  });

  it("refuses an unknown operation", () => {
    const unknown = { op: "merge", path: "" } as unknown as JsonPatchOperation;
    expect(() => applyPatch({}, [unknown])).toThrow(/unknown operation/);
  });

  it.each<readonly [string, JsonValue, JsonValue]>([
    ["equal documents", { a: [1, { b: 2 }] }, { a: [1, { b: 2 }] }],
    ["changed members", { a: 1, b: 2, "c/d": 3 }, { a: 1, b: 3, "e~f": 4 }],
    ["a grown array", { a: [1] }, { a: [1, 2, 3] }],
    ["a shrunk array", { a: [1, 2, 3] }, { a: [1] }],
    ["a changed type", { a: [1] }, { a: { 0: 1 } }],
    ["scalars", "x", 2],
  ])("createPatch round-trips %s", (_name, from, to) => {
    const patch = createPatch(from, to);
    expect(applyPatch(from, patch)).toEqual(to);
  });

  it("escapes member names in the paths it writes", () => {
    expect(createPatch({}, { "a/b~c": 1 })).toEqual([
      { op: "add", path: "/a~1b~0c", value: 1 },
    ]);
  });
});
