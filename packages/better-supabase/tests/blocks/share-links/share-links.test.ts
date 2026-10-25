import { describe, expect, it } from "vitest";

import { createShareLinks } from "../../../src/blocks/share-links/index.ts";

const FILE = { type: "files", id: "f1" };

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, unknown][] = [];

  return {
    calls,
    call(schema: string, fn: string, args?: unknown) {
      expect(schema).toBe("app");
      calls.push([fn, args]);

      return Promise.resolve(results[fn]);
    },
  };
}

describe("createShareLinks", () => {
  it("creates a share link, records a view and stores user state", async () => {
    const transport = fakeTransport({
      create_share_link: { id: "s1", token: "once" },
      revoke_share_link: true,
      resolve_share_link: {
        id: "s1",
        organizationId: "org",
        subjectType: "files",
        subjectId: "f1",
        role: "edit",
        versionId: "v1",
        expiresAt: "2026-11-01T00:00:00Z",
      },
      record_view: true,
      list_share_links: [],
      set_user_state: true,
    });

    const links = createShareLinks({ transport, schema: "app", tenant: "org" });

    expect((await links.create(FILE, "edit").orThrow()).token).toBe("once");
    expect(await links.revoke("s1").orThrow()).toBe(true);
    const resolved = await links.resolve("once").orThrow();
    expect(resolved).toMatchObject({
      id: "s1",
      organizationId: "org",
      subject: FILE,
      role: "edit",
      versionId: "v1",
    });
    expect(resolved?.expiresAt?.toString()).toBe("2026-11-01T00:00:00Z");
    expect((await links.create(FILE, { versionId: "v1" }).orThrow()).id).toBe(
      "s1",
    );
    expect(await links.recordView(FILE, "user", "u1").orThrow()).toBe(true);
    expect(await links.list(FILE).orThrow()).toEqual([]);
    expect(await links.setState(FILE, true).orThrow()).toBe(true);
    expect(transport.calls).toContainEqual([
      "record_view",
      {
        tenant: "org",
        subject_type: "files",
        subject_id: "f1",
        viewer_kind: "user",
        viewer: "u1",
      },
    ]);
    expect(transport.calls).toContainEqual([
      "set_user_state",
      { subject_type: "files", subject_id: "f1", starred: true },
    ]);
  });

  it("sends a share link's expiry", async () => {
    const transport = fakeTransport({
      create_share_link: { id: "s1", token: "once" },
    });

    const links = createShareLinks({
      transport,
      schema: "app",
      tenant: () => "org",
    });

    await links
      .create(FILE, {
        expiresAt: Temporal.Instant.from("2026-11-01T00:00:00Z"),
      })
      .orThrow();
    await links.create(FILE).orThrow();
    expect(transport.calls.map(([, args]) => args)).toEqual([
      expect.objectContaining({
        tenant: "org",
        subject_type: "files",
        subject_id: "f1",
        expires_at: "2026-11-01T00:00:00Z",
      }),
      expect.objectContaining({ expires_at: null, role: "view" }),
    ]);
  });

  it("fails without a tenant", async () => {
    const transport = fakeTransport({ list_share_links: [] });
    const links = createShareLinks({ transport, schema: "app" });

    for (const result of [
      await links.create(FILE),
      await links.recordView(FILE, "user"),
    ]) {
      expect(result.error).toMatchObject({
        kind: "invalid_request",
        hint: "TENANT_REQUIRED",
      });
    }

    expect(transport.calls).toEqual([]);
    expect(await links.list(FILE).orThrow()).toEqual([]);
  });

  it("creates a link for a caller-made hash, finds it and lists full rows", async () => {
    const fake = fakeTransport({
      create_share_link: { id: "l1", token: null },
      find_share_link: {
        id: "l1",
        organizationId: "org-1",
        subjectType: "thread",
        subjectId: "t1",
        role: "view",
        createdBy: "u1",
      },
      list_share_links: [
        {
          id: "l1",
          role: "view",
          expiresAt: null,
          revokedAt: null,
          organizationId: "org-1",
          subjectType: "thread",
          subjectId: "t1",
          createdBy: "u1",
          createdAt: "2026-01-01T00:00:00Z",
        },
      ],
    });

    const links = createShareLinks({
      transport: fake,
      schema: "app",
      tenant: "org-1",
    });

    const thread = { type: "thread", id: "t1" };

    expect(await links.createHashed(thread, "a".repeat(64)).orThrow()).toEqual({
      id: "l1",
      fields: {},
    });
    expect(await links.find("a".repeat(64)).orThrow()).toEqual({
      id: "l1",
      organizationId: "org-1",
      subject: thread,
      role: "view",
      createdBy: "u1",
    });

    const [row] = await links.list(thread, { includeRevoked: false }).orThrow();

    expect(row?.subject).toEqual(thread);
    expect(row?.createdBy).toBe("u1");
    expect(row?.createdAt?.toString()).toBe("2026-01-01T00:00:00Z");
    expect(
      fake.calls.map(([fn, args]) => {
        const record = args as Record<string, unknown>;

        return [fn, record["token_hash"] ?? record["include_revoked"]];
      }),
    ).toEqual([
      ["create_share_link", "a".repeat(64)],
      ["find_share_link", "a".repeat(64)],
      ["list_share_links", false],
    ]);
  });
});
