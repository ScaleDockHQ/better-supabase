import { describe, expect, it } from "vitest";

import { createTrash } from "../../../src/blocks/trash/index.ts";

function transport(results: Record<string, (args: unknown) => unknown>) {
  const calls: [string, unknown][] = [];
  return {
    calls,
    call(schema: string, fn: string, args: unknown) {
      expect(schema).toBe("app");
      calls.push([fn, args]);
      const result = results[fn];
      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }
      return Promise.resolve(result(args));
    },
  };
}

const ITEM = {
  id: "t1",
  batchId: "b1",
  count: 3,
  subjectType: "project",
  subjectId: "p1",
  title: "Launch",
  trashedBy: "u1",
  trashedAt: "2026-10-01T00:00:00Z",
  purgeAfter: "2026-10-31T00:00:00Z",
};

describe("trash client", () => {
  it("trashes, lists, restores and purges", async () => {
    const fake = transport({
      trash: () => ({ id: "t1", batchId: "b1", count: 3 }),
      restore_trash: () => ({ id: "t1", batchId: "b1", count: 3 }),
      list_trash: () => [
        ITEM,
        {
          ...ITEM,
          id: "t2",
          title: null,
          trashedBy: null,
          purgeAfter: null,
        },
      ],
      purge_trash: () => 3,
    });
    const trash = createTrash({ transport: fake, schema: "app" });
    expect(await trash.trash("o", "project", "p1").orThrow()).toEqual({
      id: "t1",
      batchId: "b1",
      count: 3,
    });
    const listed = await trash
      .list("o", {
        subjectType: "project",
        pageSize: 10,
        before: Temporal.Instant.from("2026-10-02T00:00:00Z"),
      })
      .orThrow();
    expect(listed[0]).toMatchObject({ title: "Launch", trashedBy: "u1" });
    expect(listed[0]!.purgeAfter?.toString()).toBe("2026-10-31T00:00:00Z");
    expect(listed[1]).not.toHaveProperty("title");
    expect(listed[1]).not.toHaveProperty("purgeAfter");
    expect(await trash.restore("t1").orThrow()).toMatchObject({ count: 3 });
    expect(await trash.purge("t1").orThrow()).toBe(3);
    await trash.list("o").orThrow();
    expect(fake.calls).toEqual([
      ["trash", { tenant: "o", subject_type: "project", subject_id: "p1" }],
      [
        "list_trash",
        {
          tenant: "o",
          subject_type: "project",
          page_size: 10,
          before: "2026-10-02T00:00:00Z",
        },
      ],
      ["restore_trash", { item_id: "t1" }],
      ["purge_trash", { item_id: "t1" }],
      [
        "list_trash",
        { tenant: "o", subject_type: null, page_size: null, before: null },
      ],
    ]);
  });

  it("runs hooks around a method", async () => {
    const seen: string[] = [];
    const trash = createTrash({
      transport: transport({ purge_trash: () => 1 }),
      schema: "app",
      logger: console,
      hooks: {
        purge: {
          before: () => {
            seen.push("before");
          },
        },
      },
    });
    await trash.purge("t1").orThrow();
    expect(seen).toEqual(["before"]);
  });
});
