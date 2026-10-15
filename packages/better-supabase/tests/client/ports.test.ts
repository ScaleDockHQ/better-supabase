import { describe, expect, it, vi } from "vitest";

import type { PickedFile } from "../../src/client/ports.ts";

import { memoryStorage, storageUpload } from "../../src/client/ports.ts";

const file = (
  read: () => Promise<Blob | ArrayBuffer>,
  type?: string,
): PickedFile => ({
  name: "a.png",
  type,
  size: 3,
  uri: undefined,
  read,
});

function fakeStorage(answer: { data?: { path: string }; error?: unknown }) {
  const upload = vi.fn(async () => ({
    data: answer.data ?? null,
    error: answer.error ?? null,
  }));
  const from = vi.fn(() => ({ upload }));
  // SAFETY: storageUpload calls only `storage.from(bucket).upload`.
  const supabase = { storage: { from } } as never;
  return { supabase, from, upload };
}

describe("memoryStorage", () => {
  it("gets, sets and removes values", async () => {
    const storage = memoryStorage({ a: "1" });
    expect(await storage.get("a")).toBe("1");
    await storage.set("b", "2");
    expect(await storage.get("b")).toBe("2");
    await storage.remove("a");
    expect(await storage.get("a")).toBeNull();
  });
});

describe("storageUpload", () => {
  it("uploads the picked bytes with the file's type", async () => {
    const { supabase, from, upload } = fakeStorage({
      data: { path: "u1/a.png" },
    });
    const bytes = new ArrayBuffer(3);
    const result = await storageUpload(supabase)(
      file(async () => bytes, "image/png"),
      { bucket: "avatars", path: "u1/a.png", upsert: true },
    );
    expect(result).toMatchObject({ ok: true, data: { path: "u1/a.png" } });
    expect(from).toHaveBeenCalledWith("avatars");
    expect(upload).toHaveBeenCalledWith("u1/a.png", bytes, {
      contentType: "image/png",
      upsert: true,
    });
  });

  it("maps a storage error and a failed read", async () => {
    const denied = fakeStorage({
      error: {
        message: "new row violates row-level security policy",
        statusCode: "403",
      },
    });
    const refused = await storageUpload(denied.supabase)(
      file(async () => new Blob(["x"])),
      { bucket: "avatars", path: "a" },
    );
    expect(refused.ok).toBe(false);
    expect(denied.upload).toHaveBeenCalledWith("a", expect.any(Blob), {});

    const unread = await storageUpload(fakeStorage({}).supabase)(
      file(() => Promise.reject(new Error("gone"))),
      { bucket: "avatars", path: "a" },
    );
    expect(unread).toMatchObject({ ok: false, error: { message: "gone" } });
  });
});
