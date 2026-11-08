import { describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { moduleContext } from "../../src/sql/module-context.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";

const keyOf = (layout: BlockSqlLayout): string =>
  moduleContext("tags", layout, ["memberships", "tags"]).permissionKey(
    "read",
    "tags.read",
  );

describe("the default permission key of a block action", () => {
  it("is read from a registered module", () => {
    expect(SQL_MODULES["tags"]).toBeDefined();
  });

  it("is block.action without a provider catalog", () => {
    expect(keyOf({})).toBe("tags.read");
  });

  it("is block.action when the provider lists it", () => {
    expect(keyOf({ permissionCatalog: ["tags.read", "tag.read"] })).toBe(
      "tags.read",
    );
  });

  it("falls back to resource.action when only that key is listed", () => {
    expect(keyOf({ permissionCatalog: ["tag.read"] })).toBe("tag.read");
  });

  it("stays block.action when the provider lists neither", () => {
    expect(keyOf({ permissionCatalog: ["people.read"] })).toBe("tags.read");
  });

  it("keeps an explicit remap whatever the catalog lists", () => {
    expect(
      keyOf({
        permissionCatalog: ["tag.read", "labels.read"],
        modules: { tags: { permissions: { read: "labels.read" } } },
      }),
    ).toBe("labels.read");
  });
});
