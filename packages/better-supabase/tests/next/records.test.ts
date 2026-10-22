import { beforeEach, describe, expect, it, vi } from "vitest";

import {
  invalidateSection,
  recordTag,
  sectionTag,
} from "../../src/next/records.ts";

const mocks = vi.hoisted(() => ({
  updateTag: vi.fn<(tag: string) => undefined>(),
  revalidateTag:
    vi.fn<(tag: string, profile: string | { expire?: number }) => undefined>(),
}));

vi.mock(import("next/cache.js"), () => ({
  updateTag: mocks.updateTag,
  revalidateTag: mocks.revalidateTag,
}));

const customer = { type: "customer", id: "42" };

describe("record cache tags", () => {
  beforeEach(() => {
    mocks.updateTag.mockReset();
    mocks.revalidateTag.mockReset();
  });

  it("scopes the record and section tags to a tenant", () => {
    expect(recordTag(customer)).toBe("bsb:record:customer:42");
    expect(recordTag(customer, { tenant: null })).toBe(
      "bsb:record:customer:42",
    );
    expect(recordTag(customer, { tenant: "org1" })).toBe(
      "bsb:record@org1:customer:42",
    );
    expect(sectionTag(customer, "comments", { tenant: "org1" })).toBe(
      "bsb:record@org1:customer:42#comments",
    );
  });

  it("invalidates the section and the record with updateTag in an action", () => {
    invalidateSection(customer, "tags", { tenant: "org1" });

    expect(mocks.updateTag.mock.calls).toEqual([
      ["bsb:record@org1:customer:42#tags"],
      ["bsb:record@org1:customer:42"],
    ]);
  });

  it("falls back to revalidateTag outside a Server Action", () => {
    mocks.updateTag.mockImplementation(() => {
      throw new Error("not in an action");
    });

    invalidateSection(customer, "tags", { revalidate: "max" });

    expect(mocks.revalidateTag.mock.calls).toEqual([
      ["bsb:record:customer:42#tags", "max"],
      ["bsb:record:customer:42", "max"],
    ]);
  });
});
