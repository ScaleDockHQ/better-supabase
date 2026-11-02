import { describe, expect, it } from "vitest";

import { createTags } from "../../../src/blocks/tags/index.ts";

const DEAL = { type: "deal", id: "d1" };

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

describe("createTags", () => {
  it("sends the subject and the block's tenant", async () => {
    const fake = fakeTransport({ tag: true, subject_tags: [] });
    const tags = createTags({ transport: fake.transport, tenant: "org-1" });

    expect(await tags.attach({ record: DEAL, tagId: "g1" }).orThrow()).toBe(
      true,
    );
    expect(await tags.list({ on: DEAL }).orThrow()).toEqual([]);
    expect(fake.calls).toEqual([
      [
        "tag",
        {
          tenant: "org-1",
          subject_type: "deal",
          subject_id: "d1",
          tag_id: "g1",
        },
      ],
      [
        "subject_tags",
        { tenant: "org-1", subject_type: "deal", subject_id: "d1" },
      ],
    ]);
  });

  it("fails without a tenant", async () => {
    const fake = fakeTransport({ list_tags: [], delete_tag: true });
    const session: { tenant?: string } = {};

    const tags = createTags({
      transport: fake.transport,
      tenant: () => session.tenant,
    });

    expect(await tags.list()).toMatchObject({
      ok: false,
      error: { kind: "invalid_request", hint: "TENANT_REQUIRED" },
    });
    expect(await tags.detach({ record: DEAL, tagId: "g1" })).toMatchObject({
      ok: false,
    });
    expect(fake.calls).toHaveLength(0);
    expect(await tags.delete("g1").orThrow()).toBe(true);
    session.tenant = "org-2";
    expect(await tags.list({ kind: "deal" }).orThrow()).toEqual([]);
    expect(fake.calls.at(-1)).toEqual([
      "list_tags",
      { tenant: "org-2", kind: "deal" },
    ]);
  });

  it("sends a caller's slug and a patch only when they are given", async () => {
    const fake = fakeTransport({
      create_tag: { id: "g1", slug: "hot-leads" },
      update_tag: true,
    });

    const tags = createTags({ transport: fake.transport, tenant: "org-1" });

    await tags
      .create({ kind: "deal", name: "Hot", slug: "hot-leads" })
      .orThrow();
    await tags.update({ id: "g1", patch: { name: "Warm" } }).orThrow();
    await tags
      .update({ id: "g1", patch: { color: null, slug: "warm" } })
      .orThrow();

    expect(fake.calls.map(([, args]) => args)).toEqual([
      {
        tenant: "org-1",
        kind: "deal",
        name: "Hot",
        color: null,
        description: null,
        slug: "hot-leads",
        fields: undefined,
      },
      { tag_id: "g1", name: "Warm", fields: undefined },
      {
        tag_id: "g1",
        name: null,
        patch: { slug: "warm", color: null },
        fields: undefined,
      },
    ]);
  });
});
