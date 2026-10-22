import { describe, expect, it, vi } from "vitest";

import type { ResolvedSubject } from "../../../src/blocks/subjects/subjects.ts";
import type { SubjectRef } from "../../../src/schema/types.ts";

import {
  batchSubjects,
  createSubjectsController,
} from "../../../src/blocks/subjects/client.ts";
import {
  failed,
  fakeAuth,
  flush,
  mount,
  resolved,
} from "../../fixtures/ports.ts";

const resolver = () => ({
  resolve: vi.fn((refs: readonly SubjectRef[]) =>
    resolved<Readonly<Record<string, ResolvedSubject>>>(
      Object.fromEntries(
        refs.map((ref) => [
          `${ref.type}:${ref.id}`,
          { ...ref, title: ref.id.toUpperCase() },
        ]),
      ),
    ),
  ),
});

describe("batchSubjects", () => {
  it("joins the calls of one tick and gives each caller its own refs", async () => {
    const inner = resolver();
    const batched = batchSubjects(inner);

    const [first, second] = await Promise.all([
      batched.resolve([{ type: "task", id: "a" }]),
      batched.resolve([
        { type: "task", id: "a" },
        { type: "note", id: "b" },
      ]),
    ]);

    expect(inner.resolve).toHaveBeenCalledOnce();
    expect(first.ok && Object.keys(first.data)).toEqual(["task:a"]);
    expect(second.ok && Object.keys(second.data)).toEqual(["task:a", "note:b"]);
  });

  it("passes an error to every caller of the batch", async () => {
    const batched = batchSubjects({
      resolve: () => failed<Readonly<Record<string, ResolvedSubject>>>("down"),
    });

    const results = await Promise.all([
      batched.resolve([{ type: "task", id: "a" }]),
      batched.resolve([{ type: "task", id: "b" }]),
    ]);

    expect(results.map((result) => result.ok)).toEqual([false, false]);
  });

  it("leaves out a subject the source didn't return", async () => {
    const batched = batchSubjects({
      resolve: () => resolved<Readonly<Record<string, ResolvedSubject>>>({}),
    });

    const result = await batched.resolve([{ type: "task", id: "a" }]);

    expect(result.ok && result.data).toEqual({});
  });
});

describe("createSubjectsController errors", () => {
  it("keeps the error of a failed load", async () => {
    const { view, unmount } = mount(
      createSubjectsController({
        client: {
          resolve: () =>
            failed<Readonly<Record<string, ResolvedSubject>>>("down"),
        },
        auth: fakeAuth(),
        refs: [{ type: "task", id: "a" }],
      }),
    );

    await flush();
    expect(view().error).toBeDefined();
    unmount();
  });
});

describe("createSubjectsController", () => {
  it("resolves the refs for the signed-in user", async () => {
    const client = resolver();

    const { view, unmount } = mount(
      createSubjectsController({
        client,
        auth: fakeAuth(),
        refs: [{ type: "task", id: "a" }],
      }),
    );

    await flush();
    expect(view().subjects).toEqual({
      "task:a": { type: "task", id: "a", title: "A" },
    });
    unmount();
  });

  it("settles on an empty map without refs", async () => {
    const client = resolver();

    const { view, unmount } = mount(
      createSubjectsController({ client, auth: fakeAuth(), refs: [] }),
    );

    await flush();
    expect(view().subjects).toEqual({});
    expect(client.resolve).not.toHaveBeenCalled();
    unmount();
  });
});
