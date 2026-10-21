---
"better-supabase": minor
---

Crop, show and download stored images through Storage image transformations. See [Image transformations](https://bettersupabase.com/docs/platform/storage#image-transformations).

- `defineBucket` takes `variants`, named transforms such as `thumb: { width: 160, height: 160, resize: "cover" }`. `renderUrl`, `signedUrl` and `publicUrl` accept a variant name wherever they took a transform, and the names are typed. `defineBucket` refuses a side outside 1 to 2500 or a quality outside 20 to 100.
- `avatarBucket()` and `organizationLogoBucket()` come with `sm`, `md` and `lg` variants: center-cropped squares of 48, 96 and 256 for avatars, and squares of 64, 128 and 256 that fit the whole logo. Pass `variants` to replace them.
- `useImage(bucket, target, variant)` in `better-supabase/react` returns `src`, a `srcSet` at 1x and 2x, `width` and `height`. Public buckets build the URLs while rendering; private buckets sign them and sign again before they expire.
- `storageImageSrcSet({ url })` in `better-supabase/storage` builds a `srcset` for a public Storage URL.
- New types: `ImageTransform`, `ImageVariant`, `ImageSource`, `StorageImage` and `UseImageOptions`.
- Fix: the `better-supabase/next/image` loader and `storageImageUrl` keep a crop's shape. When `src` carries a `width` and `height`, the height scales with each requested width, so a square crop stays square. A size over 2500 now shrinks both sides by the same factor instead of clamping the width alone.
