import { describe, expect, it } from "vitest";

import { storageImageUrl } from "../../src/storage/image-url.ts";

const URL_BASE = "https://abcdefghijklmnopqrst.supabase.co";

describe("storageImageUrl", () => {
  const imageUrl = storageImageUrl({ url: URL_BASE, resize: "contain" });

  it("renders public objects at a width, height and quality", () => {
    expect(
      imageUrl(`${URL_BASE}/storage/v1/object/public/avatars/me.png`, {
        width: 96,
        height: 9000,
        quality: 101,
      }),
    ).toBe(
      `${URL_BASE}/storage/v1/render/image/public/avatars/me.png?width=96&height=2500&quality=100&resize=contain`,
    );
  });

  it("returns undefined for URLs that are not public Storage objects", () => {
    expect(imageUrl("/local.png", { width: 10 })).toBeUndefined();
    expect(
      imageUrl(`${URL_BASE}/storage/v1/object/sign/avatars/me.png?token=t`, {
        width: 10,
      }),
    ).toBeUndefined();
  });
});
