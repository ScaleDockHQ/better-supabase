import { describe, expect, it, vi } from "vitest";

import {
  bySubjectType,
  optionalSubjectRefOf,
  subjectIdsByType,
  subjectKey,
  subjectRefOf,
} from "../../src/core/block-subjects.ts";
import { dbError } from "../../src/core/errors.ts";
import { AsyncResult } from "../../src/core/result.ts";

describe("subject refs from rows", () => {
  it("reads the subject columns", () => {
    expect(subjectRefOf("deal", "d1")).toEqual({ type: "deal", id: "d1" });
    expect(optionalSubjectRefOf("deal", 7)).toEqual({ type: "deal", id: "7" });
    expect(optionalSubjectRefOf(null, null)).toBeUndefined();
    expect(optionalSubjectRefOf("", "d1")).toBeUndefined();
  });

  it("keys a subject as type:id", () => {
    expect(subjectKey({ type: "deal", id: "d1" })).toBe("deal:d1");
  });
});

describe("subjectIdsByType", () => {
  it("groups ids by type in first-seen order without repeats", () => {
    const grouped = subjectIdsByType([
      { type: "deal", id: "d1" },
      { type: "ticket", id: "t1" },
      { type: "deal", id: "d2" },
      { type: "deal", id: "d1" },
    ]);

    expect([...grouped]).toEqual([
      ["deal", ["d1", "d2"]],
      ["ticket", ["t1"]],
    ]);
  });
});

describe("bySubjectType", () => {
  it("makes one call per type and keys the merged result by type:id", async () => {
    const call = vi.fn((type: string, ids: readonly string[]) =>
      AsyncResult.ok(
        Object.fromEntries(ids.map((id) => [id, `${type}/${id}`])),
      ),
    );

    const result = await bySubjectType(
      [
        { type: "deal", id: "1" },
        { type: "ticket", id: "1" },
        { type: "deal", id: "2" },
      ],
      call,
    );

    expect(call).toHaveBeenCalledTimes(2);
    expect(result).toMatchObject({
      ok: true,
      data: { "deal:1": "deal/1", "deal:2": "deal/2", "ticket:1": "ticket/1" },
    });
  });

  it("returns the first error", async () => {
    const result = await bySubjectType([{ type: "deal", id: "1" }], () =>
      AsyncResult.err(dbError("forbidden", "no")),
    );

    expect(result.ok).toBe(false);
  });

  it("makes no call for no subjects", async () => {
    const call = vi.fn(() => AsyncResult.ok({}));

    expect(await bySubjectType([], call)).toMatchObject({ ok: true, data: {} });
    expect(call).not.toHaveBeenCalled();
  });
});
