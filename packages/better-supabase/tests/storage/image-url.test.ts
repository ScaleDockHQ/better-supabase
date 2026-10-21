import { describe, expect, it } from "vitest";

import {
  storageImageSrcSet,
  storageImageUrl,
} from "../../src/storage/image-url.ts";
import { scaleTransform } from "../../src/storage/variants.ts";

const URL_BASE = "https://abcdefghijklmnopqrst.supabase.co";
const OBJECT = `${URL_BASE}/storage/v1/object/public/avatars/me.png`;
const RENDER = `${URL_BASE}/storage/v1/render/image/public/avatars/me.png`;

describe("storageImageUrl", () => {
  const imageUrl = storageImageUrl({ url: URL_BASE, resize: "contain" });

  it("renders public objects at a width, height and quality", () => {
    expect(imageUrl(OBJECT, { width: 96, height: 128, quality: 101 })).toBe(
      `${RENDER}?width=96&height=128&quality=100&resize=contain`,
    );
  });

  it("scales both sides down by one factor at the 2500 limit", () => {
    expect(imageUrl(OBJECT, { width: 5000, height: 2500 })).toBe(
      `${RENDER}?width=2500&height=1250&resize=contain`,
    );
  });

  it("keeps a crop's aspect ratio when only the width changes", () => {
    const crop = storageImageUrl({ url: URL_BASE });

    expect(
      crop(`${RENDER}?width=400&height=200&resize=cover`, { width: 1080 }),
    ).toBe(`${RENDER}?width=1080&height=540&resize=cover`);
    expect(crop(`${RENDER}?height=200`, { width: 640 })).toBe(
      `${RENDER}?height=200&width=640`,
    );
    expect(crop(OBJECT, { width: 640 })).toBe(`${RENDER}?width=640`);
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

describe("storageImageSrcSet", () => {
  const srcSet = storageImageSrcSet({ url: URL_BASE });

  it("lists the image at each density", () => {
    expect(srcSet(OBJECT, { width: 96, height: 96 })).toBe(
      `${RENDER}?width=96&height=96 1x, ${RENDER}?width=192&height=192 2x`,
    );
    expect(
      srcSet(`${RENDER}?width=300&height=100`, { width: 300 }, [1, 3]),
    ).toBe(
      `${RENDER}?width=300&height=100 1x, ${RENDER}?width=900&height=300 3x`,
    );
  });

  it("returns undefined for other URLs", () => {
    expect(srcSet("/local.png", { width: 96 })).toBeUndefined();
  });
});

describe("scaleTransform", () => {
  it("scales width and height together and stops at 2500", () => {
    expect(
      scaleTransform({ width: 96, height: 48, resize: "cover" }, 2),
    ).toEqual({ width: 192, height: 96, resize: "cover" });
    expect(scaleTransform({ width: 2000, height: 1000 }, 2)).toEqual({
      width: 2500,
      height: 1250,
    });
    expect(scaleTransform({ quality: 80 }, 2)).toEqual({ quality: 80 });
  });
});
