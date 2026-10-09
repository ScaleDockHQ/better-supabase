import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";

import {
  blockCall,
  credentialRefOf,
  eachLimit,
  enumOrThrow,
  instantArg,
  mappersOf,
  notFoundError,
  pageOf,
  optionalInstant,
  optionalText,
  randomToken,
  recordOf,
  recordOrEmpty,
  recordsOf,
  requiredInstant,
  sha256Hex,
  stringsOf,
  textOf,
} from "../../src/core/block-helpers.ts";

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

describe("eachLimit", () => {
  it("keeps at most `limit` calls in flight and visits every item", async () => {
    let inFlight = 0;
    let peak = 0;
    const seen: number[] = [];
    await eachLimit([1, 2, 3, 4, 5], 2, async (item, index) => {
      inFlight += 1;
      peak = Math.max(peak, inFlight);
      await new Promise((resolve) => {
        setTimeout(resolve, 1);
      });
      seen[index] = item;
      inFlight -= 1;
    });
    expect(peak).toBe(2);
    expect(seen).toEqual([1, 2, 3, 4, 5]);
  });

  it("starts nothing new after a rejection and rethrows it", async () => {
    const started: number[] = [];
    await expect(
      eachLimit([1, 2, 3, 4], 1, async (item) => {
        started.push(item);
        if (item === 2) throw new Error("boom");
      }),
    ).rejects.toThrow("boom");
    expect(started).toEqual([1, 2]);
    await eachLimit([], 4, async () => {
      throw new Error("never");
    });
  });
});

describe("row decoders", () => {
  it("reads enums, objects, refs and required instants", () => {
    expect(enumOrThrow("a", ["a", "b"], "letter")).toBe("a");
    expect(() => enumOrThrow("c", ["a", "b"], "letter")).toThrow(
      'unknown letter "c"',
    );
    expect(recordOrEmpty({ a: 1 })).toEqual({ a: 1 });
    expect(recordOrEmpty([1])).toEqual({});
    expect(credentialRefOf({ provider: "vault", secret: "s" })).toEqual({
      provider: "vault",
      secret: "s",
    });
    expect(credentialRefOf({ secret: "s" })).toBeUndefined();
    expect(
      requiredInstant("2026-01-01T00:00:00Z", "createdAt").toString(),
    ).toBe("2026-01-01T00:00:00Z");
    expect(() => requiredInstant(null, "createdAt")).toThrow(
      "createdAt is missing",
    );
  });

  it("builds not_found errors and reads the mappers alias", () => {
    expect(notFoundError("No such row", "ROW_NOT_FOUND")).toMatchObject({
      kind: "not_found",
      message: "No such row",
      hint: "ROW_NOT_FOUND",
    });
    expect(notFoundError("No such row").hint).toBeUndefined();
    const mapper = () => undefined;
    expect(mappersOf({ errorMappers: [mapper] })).toEqual([mapper]);
    expect(mappersOf({ mappers: [mapper], errorMappers: [] })).toEqual([
      mapper,
    ]);
    expect(mappersOf({})).toEqual([]);
  });
});

describe("pageOf", () => {
  it("prefers limit and cursor, then the deprecated names", () => {
    expect(pageOf({ limit: 5, cursor: "c", after: "a", size: 9 })).toEqual({
      limit: 5,
      cursor: "c",
    });
    expect(pageOf({ size: 9, before: 3 })).toEqual({ limit: 9, cursor: 3 });
    expect(pageOf({ after: "a" })).toEqual({ limit: undefined, cursor: "a" });
    expect(pageOf()).toEqual({ limit: undefined, cursor: undefined });
  });
});
