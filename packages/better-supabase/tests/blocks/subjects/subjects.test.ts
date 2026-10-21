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
});
