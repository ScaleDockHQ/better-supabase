import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";

import {
  expandPermissionBitset,
  md5Hex,
  permissionCatalog,
} from "../../src/auth/permission-bitset.ts";
import { permissionsOf } from "../../src/auth/permissions.ts";

/** What `better_supabase.permission_bitset` writes: bit i of byte i / 8. */
function encode(all: readonly string[], held: readonly string[]): string {
  const bytes = new Uint8Array(Math.ceil(all.length / 8));

  for (const [index, key] of all.entries()) {
    if (held.includes(key)) {
      bytes[Math.floor(index / 8)] =
        (bytes[Math.floor(index / 8)] ?? 0) + 2 ** (index % 8);
    }
  }

  return Buffer.from(bytes).toString("base64url");
}

describe("md5Hex", () => {
  it.each([
    "",
    "a",
    "billing.read\nbilling.write",
    "é".repeat(100),
    "x".repeat(5000),
  ])("matches node:crypto for %#", (text) => {
    expect(md5Hex(text)).toBe(createHash("md5").update(text).digest("hex"));
  });
});

describe("permission bitset", () => {
  const keys = ["b.write", "a.read", "b.read", "a.write", "c.manage"];
  const catalog = permissionCatalog(keys);

  it("sorts the keys and hashes them like the hook", () => {
    expect(catalog.keys).toEqual([
      "a.read",
      "a.write",
      "b.read",
      "b.write",
      "c.manage",
    ]);
    expect(catalog.hash).toBe(
      createHash("md5")
        .update(catalog.keys.join("\n"))
        .digest("hex")
        .slice(0, 8),
    );
  });

  it("expands what the database encodes", () => {
    const held = ["a.write", "b.read", "c.manage"];
    const value = { h: catalog.hash, b: encode(catalog.keys, held) };

    expect(expandPermissionBitset(catalog, value)).toEqual(held);
  });

  it("answers undefined for another catalog or a bad value", () => {
    const b = encode(catalog.keys, ["a.read"]);

    expect(
      expandPermissionBitset(catalog, { h: "00000000", b }),
    ).toBeUndefined();
    expect(
      expandPermissionBitset(catalog, { h: catalog.hash }),
    ).toBeUndefined();
    expect(expandPermissionBitset(catalog, ["a.read"])).toBeUndefined();
    expect(
      expandPermissionBitset(catalog, { h: catalog.hash, b: "!!" }),
    ).toBeUndefined();
  });

  it("is read by permissionsOf with a catalog", () => {
    const tenant = "t1";

    const claims = {
      tenant_id: tenant,
      permissions: {
        [tenant]: { h: catalog.hash, b: encode(catalog.keys, ["a.read"]) },
      },
    };

    expect(
      permissionsOf(claims, tenant, { catalog, tenantClaim: "tenant_id" }),
    ).toEqual(["a.read"]);
    expect(
      permissionsOf(claims, tenant, { tenantClaim: "tenant_id" }),
    ).toBeUndefined();
  });
});
