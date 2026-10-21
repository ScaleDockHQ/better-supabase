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
});
