import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { blockFields } from "../../src/core/block-fields.ts";

const Fields = v.object({
  plan: v.picklist(["free", "pro"]),
  seats: v.pipe(
    v.union([v.number(), v.string()]),
    v.transform(Number),
    v.integer(),
    v.minValue(1),
  ),
});

describe("blockFields", () => {
  it("passes reads and writes through without a schema", async () => {
    const fields = blockFields(undefined, "fields");
    expect(await fields.read({ a: 1 })).toMatchObject({
      ok: true,
      data: { a: 1 },
    });
    expect(await fields.write({ a: 1 })).toMatchObject({
      ok: true,
      data: { a: 1 },
    });
  });

  it("parses reads over the row and keeps the other columns", async () => {
    const fields = blockFields(Fields, "organization fields");
    expect(
      await fields.read({ id: "1", plan: "pro", seats: "3" }),
    ).toMatchObject({ ok: true, data: { id: "1", plan: "pro", seats: 3 } });
  });

  it("returns a validation error for a row the schema rejects", async () => {
    const fields = blockFields(Fields, "organization fields");
    expect(await fields.read({ plan: "gold", seats: 1 })).toMatchObject({
      ok: false,
      error: {
        kind: "validation",
        message: "Invalid organization fields",
        issues: [{ path: ["plan"] }],
      },
    });
  });

  it("allows partial writes and parses the fields they set", async () => {
    const fields = blockFields(Fields, "fields");
    expect(await fields.write({ seats: "4" })).toMatchObject({
      ok: true,
      data: { seats: "4" },
    });
    expect(await fields.write({ plan: "free", seats: "4" })).toMatchObject({
      ok: true,
      data: { plan: "free", seats: 4 },
    });
  });

  it("rejects a write that sets a bad value", async () => {
    const fields = blockFields(Fields, "fields");
    expect(await fields.write({ plan: "gold" })).toMatchObject({
      ok: false,
      error: { kind: "validation", issues: [{ path: ["plan"] }] },
    });
  });

  it("works with an async schema", async () => {
    const fields = blockFields(
      v.objectAsync({
        locale: v.pipeAsync(
          v.string(),
          v.checkAsync((value) => Promise.resolve(value !== "fr")),
        ),
      }),
      "profile fields",
    );
    expect((await fields.read({ locale: "nl", id: "u" })).ok).toBe(true);
    expect((await fields.write({ locale: "fr" })).ok).toBe(false);
  });
});
