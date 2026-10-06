import { describe, expect, it, vi } from "vitest";

import type { BlockTransport } from "../../../src/blocks/announcements/index.ts";

import { createAnnouncements } from "../../../src/blocks/announcements/index.ts";

const row = {
  id: "a1",
  title: "Maintenance",
  body: "Tonight",
  severity: "critical",
  href: "/status",
  audience: "role",
  targets: ["admin"],
  starts_at: "2026-01-01T00:00:00Z",
  ends_at: "2026-01-02T00:00:00Z",
  dismissible: false,
  created_by: "staff",
  created_at: "2026-01-01T00:00:00Z",
  updated_at: "2026-01-01T00:00:00Z",
};

function fake(answer: (fn: string) => unknown) {
  const call = vi.fn(
    async (_schema: string, fn: string, _args: Record<string, unknown>) =>
      answer(fn),
  );
  const transport: BlockTransport = { call };
  return { call, client: createAnnouncements({ transport }) };
}

describe("createAnnouncements", () => {
  it("lists active announcements and dismisses one", async () => {
    const { call, client } = fake((fn) =>
      fn === "active_announcements"
        ? [{ ...row, severity: "unknown", body: null, href: null }]
        : true,
    );
    const [first] = await client.listActive("org").orThrow();
    expect(first).toMatchObject({
      id: "a1",
      severity: "info",
      body: "",
      href: undefined,
      dismissible: false,
    });
    expect(first?.endsAt?.toString()).toBe("2026-01-02T00:00:00Z");
    expect(call.mock.calls[0]?.[2]).toEqual({ tenant: "org" });
    await client.listActive();
    expect(call.mock.calls[1]?.[2]).toEqual({ tenant: null });
    expect(await client.dismiss("a1").orThrow()).toBe(true);
  });

  it("maps audiences both ways", async () => {
    const rows = [
      row,
      { ...row, audience: "tenant", targets: ["o1"] },
      { ...row, audience: "plan", targets: ["pro"] },
      { ...row, audience: "all", targets: [] },
    ];
    const { call, client } = fake((fn) =>
      fn === "list_announcements"
        ? rows
        : fn === "delete_announcement"
          ? true
          : row,
    );
    expect((await client.list().orThrow()).map((a) => a.audience)).toEqual([
      { type: "role", roles: ["admin"] },
      { type: "tenant", organizationIds: ["o1"] },
      { type: "plan", plans: ["pro"] },
      { type: "all" },
    ]);

    const published = await client
      .publish({
        title: "Hello",
        body: "World",
        severity: "success",
        href: "https://example.com",
        audience: { type: "tenant", organizationIds: ["o1"] },
        startsAt: Temporal.Instant.from("2026-01-01T00:00:00Z"),
        endsAt: Temporal.Instant.from("2026-01-03T00:00:00Z"),
        dismissible: true,
      })
      .orThrow();
    expect(published.createdBy).toBe("staff");
    expect(call.mock.calls[1]?.[2]).toEqual({
      id: null,
      fields: {
        title: "Hello",
        body: "World",
        severity: "success",
        href: "https://example.com",
        audience: "tenant",
        targets: ["o1"],
        starts_at: "2026-01-01T00:00:00Z",
        ends_at: "2026-01-03T00:00:00Z",
        dismissible: true,
      },
    });

    for (const audience of [
      { type: "all" },
      { type: "role", roles: ["admin"] },
      { type: "plan", plans: ["pro"] },
    ] as const) {
      await client.update("a1", { audience });
    }
    await client.update("a1", { endsAt: null, href: null });
    expect(call.mock.calls.slice(2).map((c) => c[2])).toEqual([
      { id: "a1", fields: { audience: "all", targets: [] } },
      { id: "a1", fields: { audience: "role", targets: ["admin"] } },
      { id: "a1", fields: { audience: "plan", targets: ["pro"] } },
      { id: "a1", fields: { ends_at: null, href: null } },
    ]);
    expect(await client.remove("a1").orThrow()).toBe(true);
    expect(() =>
      client.update("a1", { audience: { type: "everyone" } as never }),
    ).toThrow("Unknown audience");
  });
});
