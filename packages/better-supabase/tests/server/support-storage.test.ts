import { describe, expect, it, vi } from "vitest";

import { supportStorage } from "../../src/server/support-storage.ts";
import { fakeSql, pgError } from "../fixtures/fake-sql.ts";

const VISIBLE = "as visible";
const ENTRIES = "from unnest($2::text[])";

function fakeAdmin() {
  const download = vi.fn(() =>
    Promise.resolve({ data: new Blob(["hi"]), error: null }),
  );
  const createSignedUrl = vi.fn(() =>
    Promise.resolve({
      data: { signedUrl: "https://storage.test/signed" },
      error: null,
    }),
  );
  const list = vi.fn(() =>
    Promise.resolve({
      data: [
        {
          name: "a.pdf",
          id: "1",
          created_at: "2026-10-01T00:00:00Z",
          updated_at: "2026-10-02T00:00:00Z",
          metadata: { size: 3 },
        },
        { name: "b.pdf", id: "2", metadata: null },
        { name: "nested", id: null },
        "not an entry",
      ],
      error: null,
    }),
  );
  const from = vi.fn(() => ({ download, createSignedUrl, list }));
  return { admin: { from }, from, download, createSignedUrl, list };
}

describe("supportStorage", () => {
  it("downloads and signs only what the target may read", async () => {
    const { sql, calls } = fakeSql([
      [
        (call) => call.text.includes(VISIBLE),
        (call) => [{ visible: call.values[1] === "org/a.pdf" }],
      ],
    ]);
    const storage = fakeAdmin();
    const docs = supportStorage({ admin: storage.admin, sql }).from("docs");

    const blob = await docs.download("org/a.pdf").orThrow();
    expect(await blob.text()).toBe("hi");
    expect(calls[0]).toEqual({
      text: "select exists (select 1 from storage.objects o where o.bucket_id = $1 and o.name = $2) as visible",
      values: ["docs", "org/a.pdf"],
    });
    expect(storage.from).toHaveBeenCalledWith("docs");

    expect(
      await docs.createSignedUrl("org/a.pdf", 60, { download: true }).orThrow(),
    ).toBe("https://storage.test/signed");
    expect(storage.createSignedUrl).toHaveBeenCalledWith("org/a.pdf", 60, {
      download: true,
    });
    await docs.createSignedUrl("org/a.pdf", 60).orThrow();
    expect(storage.createSignedUrl).toHaveBeenLastCalledWith(
      "org/a.pdf",
      60,
      undefined,
    );

    expect((await docs.download("org/hidden.pdf")).error).toMatchObject({
      kind: "not_found",
      code: "SUPPORT_STORAGE_NOT_FOUND",
    });
    expect((await docs.createSignedUrl("org/hidden.pdf", 60)).ok).toBe(false);
    expect(storage.download).toHaveBeenCalledTimes(1);
  });

  it("lists the entries the target may read, folders included", async () => {
    const { sql, calls } = fakeSql([
      [
        (call) => call.text.includes(ENTRIES),
        [{ path: "org/a.pdf" }, { path: "org/nested" }],
      ],
    ]);
    const storage = fakeAdmin();
    const entries = await supportStorage({ admin: storage.admin, sql })
      .from("docs")
      .list("org/", { limit: 10 })
      .orThrow();
    expect(entries).toEqual([
      {
        name: "a.pdf",
        id: "1",
        createdAt: "2026-10-01T00:00:00Z",
        updatedAt: "2026-10-02T00:00:00Z",
        metadata: { size: 3 },
      },
      { name: "nested", id: null },
    ]);
    expect(storage.list).toHaveBeenCalledWith("org/", { limit: 10 });
    expect(calls[0]?.values).toEqual([
      "docs",
      ["org/a.pdf", "org/b.pdf", "org/nested"],
    ]);
  });

  it("lists the bucket root and skips the check for an empty folder", async () => {
    const { sql, calls } = fakeSql([
      [(call) => call.text.includes(ENTRIES), [{ path: "b.pdf" }]],
    ]);
    const storage = fakeAdmin();
    const root = await supportStorage({ admin: storage.admin, sql })
      .from("docs")
      .list()
      .orThrow();
    expect(root.map((entry) => entry.name)).toEqual(["b.pdf"]);
    expect(calls[0]?.values[1]).toEqual(["a.pdf", "b.pdf", "nested"]);

    storage.list.mockResolvedValueOnce({ data: null, error: null } as never);
    const empty = await supportStorage({ admin: storage.admin, sql })
      .from("docs")
      .list("none")
      .orThrow();
    expect(empty).toEqual([]);
    expect(calls).toHaveLength(1);
  });

  it("maps Storage and database errors", async () => {
    const storage = fakeAdmin();
    storage.download.mockResolvedValueOnce({
      data: null,
      error: { message: "Object not found", statusCode: "404" },
    } as never);
    storage.list.mockResolvedValueOnce({
      data: null,
      error: { message: "denied", statusCode: "403" },
    } as never);
    storage.createSignedUrl.mockRejectedValueOnce(new Error("offline"));
    const visible = fakeSql([[VISIBLE, [{ visible: true }]]]);
    const docs = supportStorage({
      admin: storage.admin,
      sql: visible.sql,
    }).from("docs");
    expect((await docs.download("a")).error?.kind).toBe("not_found");
    expect((await docs.list("a")).error?.kind).toBe("forbidden");
    expect((await docs.createSignedUrl("a", 60)).error?.kind).toBe(
      "unexpected",
    );
    storage.download.mockResolvedValueOnce({
      data: null,
      error: null,
    } as never);
    expect((await docs.download("a")).error?.kind).toBe("not_found");
    storage.list.mockRejectedValueOnce(new Error("offline"));
    expect((await docs.list("a")).ok).toBe(false);

    const failing = fakeSql([
      [() => true, { throws: pgError("42501", "permission denied") }],
    ]);
    const denied = supportStorage({
      admin: storage.admin,
      sql: failing.sql,
    }).from("docs");
    expect((await denied.download("a")).error?.kind).toBe("forbidden");
    expect((await denied.list("a")).error?.kind).toBe("forbidden");
    const thrown = fakeSql([[() => true, { throws: "boom" }]]);
    expect(
      (
        await supportStorage({ admin: storage.admin, sql: thrown.sql })
          .from("docs")
          .download("a")
      ).error?.kind,
    ).toBe("unexpected");
  });

  it("refuses uploads, as read-only or as not supported", async () => {
    const { sql } = fakeSql();
    const { admin } = fakeAdmin();
    expect(
      (await supportStorage({ admin, sql }).from("docs").upload("a", "x"))
        .error,
    ).toMatchObject({ kind: "forbidden", code: "SUPPORT_READ_ONLY" });
    expect(
      (
        await supportStorage({ admin, sql, readOnly: false })
          .from("docs")
          .upload("a", "x")
      ).error,
    ).toMatchObject({ kind: "unsupported", code: "SUPPORT_STORAGE_WRITES" });
  });
});
