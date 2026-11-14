import { describe, expect, it, vi } from "vitest";

import type { BlockCall } from "../../../src/core/block-helpers.ts";

import {
  invitationList,
  invitationListSurface,
  invitationRowOf,
} from "../../../src/blocks/organizations/invitation-list.ts";
import { organizationsBlock } from "../../../src/blocks/organizations/manifest.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const page = {
  items: [
    {
      id: "1",
      email: "a@x.com",
      role: "admin",
      expiresAt: "2027-01-01T00:00:00Z",
    },
  ],
  hasMore: true,
  nextCursor: ["2027-01-01T00:00:00Z", "1"],
};

function setup() {
  const call = vi.fn(
    <T>(
      _fn: string,
      _args: Readonly<Record<string, unknown>>,
      then: (value: unknown) => T | Promise<T>,
    ) =>
      AsyncResult.from(async () => ({
        ok: true as const,
        data: await then(page),
        error: null,
      })),
  );

  return {
    call,
    list: invitationList(call as unknown as BlockCall, undefined),
  };
}

describe("the invitation list contract (ADR 0923, 0924)", () => {
  it("is the surface the manifest declares", () => {
    expect(organizationsBlock.entities["invitation"]).toMatchObject(
      invitationListSurface,
    );
  });

  it("reads page_organization_invitations with the filters", async () => {
    const { call, list } = setup();

    const result = await list.page({
      organizationId: "org",
      q: "x.com",
      sort: { by: "email" },
      filters: { role: ["admin"] },
      limit: 10,
    });

    expect(call).toHaveBeenCalledWith(
      "page_organization_invitations",
      {
        tenant: "org",
        filters: {
          sort: "email",
          role: ["admin"],
          search: "x.com",
          limit: 10,
          paged: true,
        },
      },
      expect.any(Function),
    );
    expect(result.ok && result.data.items[0]).toMatchObject({
      id: "1",
      role: "admin",
    });
    expect(result.ok && result.data.hasMore).toBe(true);
  });

  it("reads the block's tenant when the call names no organization", async () => {
    const { call } = setup();
    const list = invitationList(call as unknown as BlockCall, () => "active");

    await list.count();

    expect(call).toHaveBeenCalledWith(
      "page_organization_invitations",
      { tenant: "active", filters: { count: true } },
      expect.any(Function),
    );
  });

  it("rejects a name the entity does not declare before any call", async () => {
    const { call, list } = setup();

    expect(
      await list.page({ organizationId: "org", filters: { status: ["x"] } }),
    ).toMatchObject({ ok: false, error: { kind: "invalid_input" } });
    expect(
      await list.page({ organizationId: "org", sort: { by: "role" } }),
    ).toMatchObject({ ok: false });
    expect(call).not.toHaveBeenCalled();
  });

  it("maps both row shapes", () => {
    expect(invitationRowOf({ id: "1", email: "a", role: "r" })).toStrictEqual({
      id: "1",
      email: "a",
      role: "r",
    });
    expect(
      invitationRowOf({
        id: "1",
        email: "a",
        role: "r",
        expires_at: "2027-01-01T00:00:00Z",
      }).expiresAt?.toString(),
    ).toBe("2027-01-01T00:00:00Z");
  });
});
