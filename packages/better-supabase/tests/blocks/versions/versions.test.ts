import { describe, expect, it } from "vitest";

import { createVersions } from "../../../src/blocks/versions/index.ts";

const ROW = {
  id: "v1",
  number: 1,
  subjectType: "doc",
  subjectId: "d1",
  label: null,
  source: "manual",
  frozen: false,
  contentHash: "abc",
  storagePath: null,
  createdBy: "u1",
  createdAt: "2026-10-01T00:00:00Z",
};

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

describe("versions client", () => {
  it("snapshots, lists, labels and deletes", async () => {
    const fake = transport({
      snapshot_version: () => ({
        id: "v2",
        number: 2,
        contentHash: "def",
        unchanged: false,
      }),
      list_versions: () => [
        { ...ROW, id: "v2", number: 2, label: "Final", storagePath: "a/b" },
        ROW,
      ],
      label_version: () => true,
      delete_version: () => true,
    });

    const versions = createVersions({ transport: fake, schema: "app" });
    expect(
      await versions
        .snapshot({
          organizationId: "o",
          subjectType: "doc",
          subjectId: "d1",
          content: { a: 1 },
          label: "Final",
        })
        .orThrow(),
    ).toEqual({ id: "v2", number: 2, contentHash: "def", unchanged: false });

    const listed = await versions
      .list("o", "doc", "d1", { pageSize: 10, before: 5 })
      .orThrow();

    expect(listed[0]).toMatchObject({
      label: "Final",
      storagePath: "a/b",
      createdBy: "u1",
    });
    expect(listed[1]).not.toHaveProperty("label");
    expect(listed[1]!.createdAt.toString()).toBe("2026-10-01T00:00:00Z");
    expect(await versions.label("v1", null).orThrow()).toBe(true);
    expect(await versions.delete("v1").orThrow()).toBe(true);
    expect(fake.calls[0]).toEqual([
      "snapshot_version",
      {
        tenant: "o",
        subject_type: "doc",
        subject_id: "d1",
        content: { a: 1 },
        label: "Final",
        storage_path: null,
      },
    ]);
    expect(fake.calls[1]![1]).toMatchObject({ page_size: 10, before: 5 });
  });

  it("defaults the snapshot and list arguments to null", async () => {
    const fake = transport({
      snapshot_version: () => ({
        id: "v1",
        number: 1,
        contentHash: "a",
        unchanged: true,
      }),
      list_versions: () => null,
    });

    const versions = createVersions({ transport: fake, schema: "app" });
    await versions
      .snapshot({ organizationId: "o", subjectType: "doc", subjectId: "d1" })
      .orThrow();
    expect(await versions.list("o", "doc", "d1").orThrow()).toEqual([]);
    expect(fake.calls.map(([, args]) => args)).toEqual([
      {
        tenant: "o",
        subject_type: "doc",
        subject_id: "d1",
        content: null,
        label: null,
        storage_path: null,
      },
      {
        tenant: "o",
        subject_type: "doc",
        subject_id: "d1",
        page_size: null,
        before: null,
      },
    ]);
  });

  it("restores and diffs two versions as a JSON Patch", async () => {
    const contents: Record<string, unknown> = {
      v1: { title: "A", tags: ["x"] },
      v2: { title: "B", tags: ["x", "y"] },
      v3: null,
    };

    const fake = transport({
      get_version: (args) => {
        const id = (args as { version_id: string }).version_id;

        return { ...ROW, id, content: contents[id] };
      },
      restore_version: () => ({
        id: "v3",
        number: 3,
        contentHash: "a",
        unchanged: false,
        restoredFrom: 1,
        content: { title: "A" },
      }),
    });

    const versions = createVersions({ transport: fake, schema: "app" });
    expect(await versions.restore("v1").orThrow()).toEqual({
      id: "v3",
      number: 3,
      contentHash: "a",
      unchanged: false,
      restoredFrom: 1,
      content: { title: "A" },
    });
    expect(await versions.diff("v1", "v2").orThrow()).toEqual([
      { op: "replace", path: "/title", value: "B" },
      { op: "add", path: "/tags/1", value: "y" },
    ]);
    expect(await versions.diff("v1", "v3").orThrow()).toEqual([
      { op: "replace", path: "", value: null },
    ]);
    expect((await versions.get("v1").orThrow()).content).toEqual(
      contents["v1"],
    );
  });

  it("restores the named fields only", async () => {
    const fake = transport({
      restore_version: () => ({
        id: "v4",
        number: 4,
        contentHash: "b",
        unchanged: false,
        restoredFrom: 1,
        content: { title: "A", tags: ["x", "y"] },
      }),
    });

    const versions = createVersions({ transport: fake, schema: "app" });
    expect(
      (await versions.restoreFields("v1", ["title"]).orThrow()).content,
    ).toEqual({ title: "A", tags: ["x", "y"] });
    expect(fake.calls).toEqual([
      ["restore_version", { version_id: "v1", fields: ["title"] }],
    ]);
  });

  it("rejects a row with an unknown source", async () => {
    const versions = createVersions({
      transport: transport({
        get_version: () => ({ ...ROW, source: "other" }),
      }),
      schema: "app",
    });

    const result = await versions.get("v1");
    expect(result.ok).toBe(false);
  });

  it("runs hooks around a method", async () => {
    const seen: string[] = [];

    const versions = createVersions({
      transport: transport({ delete_version: () => true }),
      schema: "app",
      hooks: {
        delete: {
          before: () => {
            seen.push("before");
          },
        },
      },
    });

    await versions.delete("v1").orThrow();
    expect(seen).toEqual(["before"]);
  });
});
