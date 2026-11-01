import { describe, expect, it, vi } from "vitest";

import type { Executor } from "../../src/core/executor.ts";

import { commentsBlock } from "../../src/blocks/comments/index.ts";
import { createBlockClient, defineBlocks } from "../../src/blocks/index.ts";

/** A `Db` stand-in whose executor records each function call. */
function fakeDb(tenant: string | undefined) {
  const rpc = vi.fn((_name: string, _args: Readonly<Record<string, unknown>>) =>
    Promise.resolve({ ok: true as const, data: [] }),
  );

  // SAFETY: the blocks only call `rpc`; `execute` never runs here.
  const executor = { name: "fake", rpc } as unknown as Executor;

  return { db: { $executor: executor, $context: { tenant } }, rpc };
}

const deal = { type: "deal", id: "d1" };

describe("createBlockClient", () => {
  it("calls through the db with the request's tenant", async () => {
    const { db, rpc } = fakeDb("org-1");
    const comments = createBlockClient(db, commentsBlock);

    expect(await comments.list({ subject: deal })).toMatchObject({
      ok: true,
      data: [],
    });
    expect(rpc).toHaveBeenCalledWith(
      "list_comments",
      expect.objectContaining({
        tenant: "org-1",
        subject_type: "deal",
        subject_id: "d1",
      }),
      expect.anything(),
    );
  });

  it("fails with TENANT_REQUIRED when the request has no tenant", async () => {
    const { db, rpc } = fakeDb(undefined);

    const result = await createBlockClient(db, commentsBlock).list({
      subject: deal,
    });

    expect(result.ok ? undefined : result.error).toMatchObject({
      hint: "TENANT_REQUIRED",
    });
    expect(rpc).not.toHaveBeenCalled();
  });

  it("takes a fixed tenant over the request's", async () => {
    const { db, rpc } = fakeDb("org-1");

    await createBlockClient(db, commentsBlock, { tenant: "org-2" }).list({
      subject: deal,
    });

    expect(rpc.mock.calls[0]?.[1]).toMatchObject({ tenant: "org-2" });
  });
});

describe("BlockSet.client", () => {
  it("builds one block of the set against a request's db", async () => {
    const set = defineBlocks(
      { comments: { schema: "better_supabase", options: {} } },
      { comments: commentsBlock },
    );

    const { db, rpc } = fakeDb("org-3");

    await set.client(db, "comments").list({ subject: deal });

    expect(rpc.mock.calls[0]?.[1]).toMatchObject({ tenant: "org-3" });
  });
});
