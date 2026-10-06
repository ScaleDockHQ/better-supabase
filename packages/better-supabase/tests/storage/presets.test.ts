import { describe, expect, expectTypeOf, it } from "vitest";

import {
  avatarBucket,
  defineBucket,
  IMAGE_TYPES,
  organizationLogoBucket,
} from "../../src/storage/index.ts";

describe("avatarBucket", () => {
  it("stores public images under the owner's id", () => {
    const avatars = avatarBucket();
    expect(avatars.id).toBe("avatars");
    expect(avatars.public).toBe(true);
    expect(avatars.policy).toBe("owner");
    expect(avatars.fileSizeLimit).toBe(2 * 1024 * 1024);
    expect(avatars.allowedMimeTypes).toEqual(IMAGE_TYPES);
    expect(avatars.path({ userId: "u1", version: "v2", ext: "png" })).toEqual({
      ok: true,
      data: "u1/avatar-v2.png",
      error: null,
    });
    expect(avatars.sql()).toContain(
      "split_part(name, '/', 1) = (select auth.uid())::text",
    );
    expectTypeOf(avatars.id).toEqualTypeOf<"avatars">();
  });

  it("takes another id, path, size and privacy", () => {
    const avatars = avatarBucket({
      id: "profile-pictures",
      path: "users/{userId}/{version}.webp",
      public: false,
      fileSizeLimit: "1MiB",
      allowedMimeTypes: ["image/webp"],
    });
    expect(avatars.public).toBe(false);
    expect(avatars.path({ userId: "u", version: "1" }).data).toBe(
      "users/u/1.webp",
    );
    expect(avatars.sql()).toContain(
      "split_part(name, '/', 2) = (select auth.uid())::text",
    );
    expectTypeOf(avatars.id).toEqualTypeOf<"profile-pictures">();
  });
});

describe("organizationLogoBucket", () => {
  it("checks the update permission through the access contract", () => {
    const logos = organizationLogoBucket();
    expect(logos.id).toBe("organization-logos");
    expect(logos.tenant).toBe("organizationId");
    const sql = logos.sql();
    expect(sql).toContain(
      "split_part(name, '/', 1) in (select t::text from better_supabase.tenant_ids_with('organization.update') t)",
    );
    expect(sql).toContain('create policy "bs_organization_logos_insert"');
    expect(sql).toContain('create policy "bs_organization_logos_delete"');
  });

  it("takes another permission, no tenant guard or a policy of its own", () => {
    expect(
      organizationLogoBucket({ permission: "branding.manage" }).sql(),
    ).toContain("tenant_ids_with('branding.manage')");
    expect(organizationLogoBucket({ tenant: false }).tenant).toBeUndefined();
    expect(organizationLogoBucket({ policy: "tenant" }).sql()).toContain(
      "split_part(name, '/', 1) = (",
    );
  });
});

describe("access bucket policies", () => {
  it("checks list and delete keys and platform scope", () => {
    const docs = defineBucket({
      id: "docs",
      path: "{teamId}/{file}",
      policy: {
        access: {
          read: "docs.read",
          list: "docs.list",
          write: "docs.write",
          delete: "docs.delete",
        },
        segment: 1,
      },
    });
    const sql = docs.sql();
    expect(sql).toContain("tenant_ids_with('docs.list')");
    expect(sql).toContain("tenant_ids_with('docs.delete')");
    expect(sql).toContain('create policy "bs_docs_list"');

    const shared = defineBucket({
      id: "shared",
      path: "{file}",
      policy: {
        access: { read: "files.read", write: "files.write" },
        scope: "platform",
      },
    });
    expect(shared.sql()).toContain(
      "(select better_supabase.is_platform('files.write'))",
    );
  });

  it("needs the tenant segment for tenant scope", () => {
    expect(() =>
      defineBucket({
        id: "x",
        path: "{file}",
        policy: { access: { read: "a", write: "b" } },
      }),
    ).toThrow(/a permission policy needs \{organizationId\}/);
  });
});
