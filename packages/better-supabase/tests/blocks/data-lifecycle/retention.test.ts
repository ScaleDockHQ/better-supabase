import { describe, expect, it } from "vitest";

import { createRetention } from "../../../src/blocks/data-lifecycle/index.ts";

const policy = {
  id: "p1",
  organization_id: "org-1",
  plan: null,
  kind: "audit",
  keep: "7 years",
  updated_at: "2026-10-16T12:00:00Z",
};

const hold = (overrides: Record<string, unknown> = {}) => ({
  id: "h1",
  organization_id: null,
  kind: "audit",
  reason: "Litigation",
  placed_by: null,
  placed_at: "2026-10-16T12:00:00Z",
  released_by: null,
  released_at: null,
  ...overrides,
});

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];
  return {
    calls,
    transport: {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([fn, { ...args }]);
        return Promise.resolve(results[fn]);
      },
    },
  };
}

describe("createRetention", () => {
  it("sets, lists and removes policies per scope", async () => {
    const { transport, calls } = fakeTransport({
      set_retention_policy: policy,
      list_retention_policies: [policy],
      remove_retention_policy: true,
    });
    const retention = createRetention({ transport });
    const set = await retention
      .setPolicy("audit", Temporal.Duration.from({ years: 7 }), {
        organizationId: "org-1",
      })
      .orThrow();
    expect(set).toMatchObject({
      kind: "audit",
      keep: "7 years",
      organizationId: "org-1",
      plan: undefined,
    });
    expect(
      set.updatedAt.equals(Temporal.Instant.from("2026-10-16T12:00:00Z")),
    ).toBe(true);
    expect(await retention.policies().orThrow()).toHaveLength(1);
    expect(
      await retention.removePolicy("audit", { plan: "pro" }).orThrow(),
    ).toBe(true);
    expect(calls).toEqual([
      [
        "set_retention_policy",
        { kind: "audit", keep: "P7Y", tenant: "org-1", plan: undefined },
      ],
      ["list_retention_policies", { kind: undefined }],
      [
        "remove_retention_policy",
        { kind: "audit", tenant: undefined, plan: "pro" },
      ],
    ]);
  });

  it("places, releases and lists legal holds", async () => {
    const released = hold({
      released_by: "u1",
      released_at: "2026-10-17T12:00:00Z",
    });
    const { transport, calls } = fakeTransport({
      place_legal_hold: hold(),
      release_legal_hold: released,
      list_legal_holds: [released],
    });
    const retention = createRetention({ transport });
    expect(
      await retention
        .placeHold({ reason: "Litigation", kind: "audit" })
        .orThrow(),
    ).toMatchObject({
      kind: "audit",
      organizationId: undefined,
      releasedAt: undefined,
    });
    const done = await retention.releaseHold("h1").orThrow();
    expect(done?.releasedBy).toBe("u1");
    expect(done?.releasedAt?.toString()).toBe("2026-10-17T12:00:00Z");
    expect(
      await retention.holds({ includeReleased: true }).orThrow(),
    ).toHaveLength(1);
    await retention.holds().orThrow();
    expect(calls).toEqual([
      [
        "place_legal_hold",
        { reason: "Litigation", tenant: undefined, kind: "audit" },
      ],
      ["release_legal_hold", { id: "h1" }],
      ["list_legal_holds", { include_released: true }],
      ["list_legal_holds", { include_released: false }],
    ]);
  });

  it("returns undefined for a hold that wasn't active", async () => {
    const retention = createRetention({
      transport: fakeTransport({ release_legal_hold: null }).transport,
    });
    expect(await retention.releaseHold("h1").orThrow()).toBeUndefined();
  });
});
