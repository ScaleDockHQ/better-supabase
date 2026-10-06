import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";

import {
  blockCall,
  instantArg,
  optionalInstant,
  optionalText,
  randomToken,
  recordOf,
  recordsOf,
  sha256Hex,
  stringsOf,
  textOf,
} from "../../src/blocks/shared.ts";

const transport = (
  answer: () => unknown,
): BlockTransport & { calls: unknown[] } => {
  const calls: unknown[] = [];
  return {
    calls,
    call: (schema, fn, args) => {
      calls.push([schema, fn, args]);
      return Promise.resolve().then(answer);
    },
  };
};

describe("blockCall", () => {
  it("calls the function in the schema and maps the value", async () => {
    const t = transport(() => 41);
    const call = blockCall(t, "app");
    const result = await call("count", { a: 1 }, (value) => Number(value) + 1);
    expect(result.ok && result.data).toBe(42);
    expect(t.calls).toEqual([["app", "count", { a: 1 }]]);
  });

  it("maps database errors, then other errors", async () => {
    const db = blockCall(
      transport(() => {
        throw Object.assign(new Error("no"), {
          code: "42501",
          hint: "THING_FORBIDDEN",
        });
      }),
    );
    const denied = await db("x", {}, () => 1);
    expect(denied).toMatchObject({
      ok: false,
      error: { kind: "forbidden", hint: "THING_FORBIDDEN" },
    });
    const other = await blockCall(
      transport(() => {
        throw new Error("boom");
      }),
    )("x", {}, () => 1);
    expect(other.ok).toBe(false);
  });
});

describe("row helpers", () => {
  it("coerces values from jsonb and pg", () => {
    expect(textOf(3)).toBe("3");
    expect(optionalText(null)).toBe(undefined);
    expect(optionalText("a")).toBe("a");
    expect(stringsOf(["a", 1])).toEqual(["a", "1"]);
    expect(stringsOf(null)).toEqual([]);
    expect(recordOf({ a: 1 }, "f")).toEqual({ a: 1 });
    expect(() => recordOf([], "f")).toThrow(/f returned/);
    expect(recordsOf(null, "f")).toEqual([]);
    expect(recordsOf([{ a: 1 }], "f")).toEqual([{ a: 1 }]);
    expect(() => recordsOf([1], "f")).toThrow(/f returned/);
    const at = "2026-10-06T12:00:00Z";
    expect(optionalInstant(at)?.toString()).toBe(at);
    expect(optionalInstant(new Date(at))?.toString()).toBe(at);
    expect(optionalInstant(null)).toBe(undefined);
    expect(optionalInstant(5)).toBe(undefined);
    expect(instantArg(undefined)).toBe(undefined);
    expect(instantArg(null)).toBe(null);
    expect(instantArg(Temporal.Instant.from(at))).toBe(at);
  });

  it("hashes with SHA-256 and makes url-safe tokens", async () => {
    expect(await sha256Hex("abc")).toBe(
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
    );
    const token = randomToken(32);
    expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(randomToken()).not.toBe(randomToken());
  });
});
