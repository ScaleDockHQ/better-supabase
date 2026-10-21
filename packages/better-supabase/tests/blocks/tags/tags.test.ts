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

    expect(await tags.tag(DEAL, "g1").orThrow()).toBe(true);
    expect(await tags.forSubject(DEAL).orThrow()).toEqual([]);
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
    expect(await tags.untag(DEAL, "g1")).toMatchObject({ ok: false });
    expect(fake.calls).toHaveLength(0);
    expect(await tags.delete("g1").orThrow()).toBe(true);
    session.tenant = "org-2";
    expect(await tags.list("deal").orThrow()).toEqual([]);
    expect(fake.calls.at(-1)).toEqual([
      "list_tags",
      { tenant: "org-2", kind: "deal" },
    ]);
  });
});
