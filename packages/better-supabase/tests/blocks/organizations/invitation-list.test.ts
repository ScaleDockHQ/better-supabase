import { describe, expect, it } from "vitest";

import {
  invitationListSurface,
  invitationList,
} from "../../../src/blocks/organizations/invitation-list.ts";
import { organizationsBlock } from "../../../src/blocks/organizations/manifest.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const rows = [
  { id: "1", email: "b@x.com", role: "member" },
  { id: "2", email: "a@x.com", role: "admin" },
  { id: "3", email: "c@y.com", role: "member" },
];

const list = invitationList((organizationId) =>
  AsyncResult.ok(organizationId === "org" ? rows : []),
);

describe("the invitation list contract (ADR 0923)", () => {
  it("is the surface the manifest declares", () => {
    expect(organizationsBlock.entities["invitation"]).toMatchObject(
      invitationListSurface,
    );
  });

  it("filters by role, searches the email and sorts by email", async () => {
    const page = await list.page({
      organizationId: "org",
      q: "x.com",
      filters: { role: ["member"] },
    });

    expect(page.ok && page.data.items.map((row) => row.id)).toStrictEqual([
      "1",
    ]);

    const sorted = await list.page({
      organizationId: "org",
      sort: { by: "email" },
    });

    expect(sorted.ok && sorted.data.items.map((row) => row.id)).toStrictEqual([
      "2",
      "1",
      "3",
    ]);
  });

  it("pages with a cursor and counts under the same filters", async () => {
    const first = await list.page({
      organizationId: "org",
      sort: { by: "email" },
      limit: 2,
    });

    expect(first.ok && first.data).toMatchObject({
      hasMore: true,
      nextCursor: ["2"],
    });

    const next = await list.page({
      organizationId: "org",
      sort: { by: "email" },
      limit: 2,
      after: ["2"],
    });

    expect(next.ok && next.data.items.map((row) => row.id)).toStrictEqual([
      "3",
    ]);
    expect(
      await list.count({ organizationId: "org", filters: { role: ["admin"] } }),
    ).toMatchObject({ ok: true, data: { value: 1, exact: true } });

    const facets = await list.facets({ organizationId: "org" });

    expect(facets.ok && facets.data[0]?.values).toStrictEqual([
      { value: "member", count: { value: 2, exact: true } },
      { value: "admin", count: { value: 1, exact: true } },
    ]);
  });

  it("rejects a name the entity does not declare", async () => {
    expect(
      await list.page({ organizationId: "org", filters: { status: ["x"] } }),
    ).toMatchObject({ ok: false, error: { kind: "invalid_input" } });
    expect(
      await list.page({ organizationId: "org", sort: { by: "role" } }),
    ).toMatchObject({ ok: false });
  });
});
