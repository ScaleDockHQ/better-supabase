import { describe, expect, it } from "vitest";

import {
  parseKeyRing,
  ringKeyFor,
  runCreatedAt,
} from "../../../src/workflow-sdk/world/crypto.ts";

const key = (fill: number): string => Buffer.alloc(32, fill).toString("base64");

/** `wrun_` plus a ULID whose time part encodes `time`. */
function runAt(time: number): string {
  const alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
  let rest = time;
  let out = "";

  for (let index = 0; index < 10; index += 1) {
    out = (alphabet[rest % 32] ?? "0") + out;
    rest = Math.floor(rest / 32);
  }

  return `wrun_${out}0000000000000000`;
}

describe("runCreatedAt", () => {
  it("reads the time of a ULID run id", () => {
    const time = Date.parse("2026-11-20T12:00:00Z");

    expect(runCreatedAt(runAt(time))).toBe(time);
  });

  it("returns undefined for an id without a ULID", () => {
    expect(runCreatedAt("wrun_1")).toBeUndefined();
    expect(runCreatedAt("wrun_!!!!!!!!!!!!!!")).toBeUndefined();
  });
});

describe("key ring", () => {
  const ring = parseKeyRing(
    JSON.stringify([
      { id: "a", key: key(1) },
      { id: "b", key: key(2), from: "2026-06-01T00:00:00Z" },
      { id: "c", key: key(3), from: "2026-12-01T00:00:00Z" },
    ]),
  );

  it("uses the latest key that started before the run", () => {
    const at = (iso: string) => ringKeyFor(ring, runAt(Date.parse(iso))).id;

    expect(at("2026-01-01T00:00:00Z")).toBe("a");
    expect(at("2026-06-01T00:00:00Z")).toBe("b");
    expect(at("2026-11-30T23:59:59Z")).toBe("b");
    expect(at("2027-01-01T00:00:00Z")).toBe("c");
  });

  it("gives a run id without a time the newest key", () => {
    expect(ringKeyFor(ring, "wrun_1").id).toBe("c");
  });

  it("rejects a ring that isn't a list of keys in order", () => {
    expect(() => parseKeyRing("nope")).toThrow("JSON array");
    expect(() => parseKeyRing("[]")).toThrow("non-empty");
    expect(() => parseKeyRing(JSON.stringify([{ id: "a" }]))).toThrow(
      "string id and key",
    );
    expect(() =>
      parseKeyRing(
        JSON.stringify([
          { id: "a", key: key(1) },
          { id: "b", key: key(2), from: "never" },
        ]),
      ),
    ).toThrow("invalid from");
    expect(() =>
      parseKeyRing(
        JSON.stringify([
          { id: "a", key: key(1) },
          { id: "b", key: key(2), from: "2026-06-01T00:00:00Z" },
          { id: "c", key: key(3), from: "2026-05-01T00:00:00Z" },
        ]),
      ),
    ).toThrow("must start after");
  });
});
