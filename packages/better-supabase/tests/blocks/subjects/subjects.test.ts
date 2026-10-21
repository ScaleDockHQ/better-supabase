import { describe, expect, it } from "vitest";

import {
  createSubjects,
  SUBJECT_TITLES_LIMIT,
} from "../../../src/blocks/subjects/index.ts";

function fakeTransport() {
  const calls: Record<string, unknown>[] = [];

  return {
    calls,
    transport: {
      call(
        _schema: string,
        _fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push({ ...args });
        const refs = args["refs"] as { type: string; id: string }[];

        return Promise.resolve(
          refs
            .filter((ref) => ref.id !== "hidden")
            .map((ref) => ({
              ...ref,
              title: `Title ${ref.id}`,
              url: ref.type === "customer" ? `/customers/${ref.id}` : null,
            })),
        );
      },
    },
  };
}

describe("createSubjects", () => {
  it("resolves titles and paths keyed by type:id, without repeats", async () => {
    const fake = fakeTransport();
    const subjects = createSubjects({ transport: fake.transport });

    const found = await subjects
      .resolve([
        { type: "customer", id: "1" },
        { type: "customer", id: "1" },
        { type: "note", id: "n1" },
        { type: "note", id: "hidden" },
      ])
      .orThrow();

    expect(found).toEqual({
      "customer:1": {
        type: "customer",
        id: "1",
        title: "Title 1",
        url: "/customers/1",
      },
      "note:n1": { type: "note", id: "n1", title: "Title n1" },
    });
    expect(fake.calls).toHaveLength(1);
  });

  it("splits more refs than one call takes", async () => {
    const fake = fakeTransport();

    const refs = Array.from({ length: SUBJECT_TITLES_LIMIT + 1 }, (_, id) => ({
      type: "task",
      id: String(id),
    }));

    const found = await createSubjects({ transport: fake.transport })
      .resolve(refs)
      .orThrow();

    expect(fake.calls).toHaveLength(2);
    expect(Object.keys(found)).toHaveLength(SUBJECT_TITLES_LIMIT + 1);
  });

  it("skips rows without a type and id, and a result that isn't a list", async () => {
    const rows: unknown[] = [
      [null, { type: "task" }, { type: "task", id: "1" }],
      { type: "task", id: "2" },
    ];

    const subjects = createSubjects({
      transport: { call: () => Promise.resolve(rows.shift()) },
    });

    expect(
      await subjects.resolve([{ type: "task", id: "1" }]).orThrow(),
    ).toEqual({ "task:1": { type: "task", id: "1" } });
    expect(
      await subjects.resolve([{ type: "task", id: "2" }]).orThrow(),
    ).toEqual({});
  });

  it("returns the database error of a failed call", async () => {
    const subjects = createSubjects({
      transport: { call: () => Promise.reject(new Error("down")) },
    });

    const result = await subjects.resolve([{ type: "task", id: "1" }]);

    expect(result.ok).toBe(false);
  });
});

describe("createSubjects summary", () => {
  const summaryTransport = (reply: unknown) => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];

    return {
      calls,
      transport: {
        call(
          _schema: string,
          fn: string,
          args: Readonly<Record<string, unknown>>,
        ) {
          calls.push({ fn, args: { ...args } });

          return Promise.resolve(reply);
        },
      },
    };
  };

  it("reads the title, counts and unread state in one call", async () => {
    const fake = summaryTransport({
      type: "customer",
      id: "1",
      title: "Acme",
      url: "/customers/1",
      counts: { comments: 3, attachments: 0, bad: "x" },
      unread: { comments: true, attachments: false, bad: 1 },
    });

    const subjects = createSubjects({ transport: fake.transport });

    const summary = await subjects
      .summary({ type: "customer", id: "1" }, ["comments", "attachments"], {
        seenAt: Temporal.Instant.from("2026-01-01T00:00:00Z"),
      })
      .orThrow();

    expect(summary).toEqual({
      type: "customer",
      id: "1",
      title: "Acme",
      url: "/customers/1",
      counts: { comments: 3, attachments: 0 },
      unread: { comments: true, attachments: false },
    });
    expect(fake.calls).toEqual([
      {
        fn: "record_summary",
        args: {
          subject_type: "customer",
          subject_id: "1",
          sections: ["comments", "attachments"],
          seen_at: "2026-01-01T00:00:00Z",
        },
      },
    ]);
  });

  it("is undefined when the caller can't read the subject", async () => {
    const fake = summaryTransport(null);
    const subjects = createSubjects({ transport: fake.transport });

    const summary = await subjects
      .summary({ type: "customer", id: "1" }, ["comments"])
      .orThrow();

    expect(summary).toBeUndefined();
    expect(fake.calls[0]?.args["seen_at"]).toBeNull();
  });

  it("keeps empty counts when the reply has none", async () => {
    const fake = summaryTransport({ type: "customer", id: "1" });
    const subjects = createSubjects({ transport: fake.transport });

    const summary = await subjects
      .summary({ type: "customer", id: "1" }, [])
      .orThrow();

    expect(summary).toEqual({
      type: "customer",
      id: "1",
      counts: {},
      unread: {},
    });
  });
});
