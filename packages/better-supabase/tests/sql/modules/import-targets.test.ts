import { describe, expect, it } from "vitest";

import { moduleBody } from "../../../src/sql/render.ts";

const imports = (targets: unknown): string | undefined =>
  moduleBody("imports", { modules: { imports: { options: { targets } } } });

const valid = {
  subjectType: "item",
  write: "app.write_item",
  updatedAt: "app.touch_item",
  ownedHash: "app.hash_item",
  naturalKey: "app.key_item",
  batch: "app.batch_item",
  refs: { sku: "product" },
  replaces: true,
  before: "app.before_item",
  after: "app.after_item",
};

describe("import target options", () => {
  it("renders a target the app declares", () => {
    const sql = imports({ item: valid });

    expect(sql).toContain("write_item");
  });

  it("refuses a target that is not a map of entities", () => {
    expect(() => imports([])).toThrow(/must map entity names/);
    expect(() => imports({ "Not A Name": valid })).toThrow(
      /not a valid entity name/,
    );
    expect(() => imports({ item: null })).toThrow(/must be \{ subjectType/);
    expect(() => imports({ item: { ...valid, subjectType: "" } })).toThrow(
      /subjectType must be a string/,
    );
    expect(() => imports({ item: { ...valid, write: "Write" } })).toThrow(
      /write must be/,
    );
    expect(() => imports({ item: { ...valid, updatedAt: "nope" } })).toThrow(
      /updatedAt must be/,
    );
    expect(() => imports({ item: { ...valid, ownedHash: "nope" } })).toThrow(
      /ownedHash must be/,
    );
    expect(() => imports({ item: { ...valid, naturalKey: "nope" } })).toThrow(
      /naturalKey must be/,
    );
    expect(() => imports({ item: { ...valid, batch: "nope" } })).toThrow(
      /batch must be/,
    );
    expect(() => imports({ item: { ...valid, replaces: false } })).toThrow(
      /replaces must be true/,
    );
    expect(() => imports({ item: { ...valid, before: "No" } })).toThrow(
      /before must be/,
    );
    expect(() => imports({ item: { ...valid, refs: [] } })).toThrow(
      /refs must map/,
    );
    expect(() =>
      imports({ item: { ...valid, refs: { "Bad Field": "product" } } }),
    ).toThrow(/refs\.Bad Field/);
    expect(() => imports({ item: { ...valid, refs: { sku: 1 } } })).toThrow(
      /refs\.sku/,
    );
  });
});
