import { describe, expect, it } from 'vitest';

import { createImageLoader } from './index.ts';

const URL_BASE = 'https://abcdefghijklmnopqrst.supabase.co';
const loader = createImageLoader({ url: `${URL_BASE}/` });

describe('createImageLoader', () => {
  it('rewrites public object URLs to render URLs', () => {
    expect(
      loader({
        src: `${URL_BASE}/storage/v1/object/public/avatars/u1/me.webp`,
        width: 640,
        quality: 75,
      }),
    ).toBe(
      `${URL_BASE}/storage/v1/render/image/public/avatars/u1/me.webp?width=640&quality=75`,
    );
  });

  it('replaces the size of render URLs and keeps other parameters', () => {
    expect(
      loader({
        src: `${URL_BASE}/storage/v1/render/image/public/avatars/u%201.png?width=10&height=300&version=4`,
        width: 3840,
        quality: 5,
      }),
    ).toBe(
      `${URL_BASE}/storage/v1/render/image/public/avatars/u%201.png?width=2500&height=300&version=4&quality=20`,
    );
  });

  it('adds the configured resize mode', () => {
    expect(
      createImageLoader({ url: URL_BASE, resize: 'contain' })({
        src: `${URL_BASE}/storage/v1/object/public/a/b.jpg`,
        width: 256,
      }),
    ).toBe(
      `${URL_BASE}/storage/v1/render/image/public/a/b.jpg?width=256&resize=contain`,
    );
  });

  it('passes signed, local and foreign URLs through', () => {
    for (const src of [
      `${URL_BASE}/storage/v1/object/sign/logos/o1/c1/logo/1.webp?token=t`,
      `${URL_BASE}/storage/v1/render/image/sign/logos/o1/c1/logo/1.webp?token=t`,
      '/logo.svg',
      'https://cdn.example.com/object/public/a/b.jpg',
    ]) {
      expect(loader({ src, width: 640 })).toBe(src);
    }
    const fallback = createImageLoader({
      url: URL_BASE,
      fallback: ({ src, width }) => `${src}?w=${width}`,
    });
    expect(fallback({ src: '/logo.png', width: 96 })).toBe('/logo.png?w=96');
  });
});
