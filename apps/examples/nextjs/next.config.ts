import type { NextConfig } from 'next';

const config: NextConfig = {
  cacheComponents: true,
  partialPrefetching: true,
  experimental: {
    // `@next/playwright`'s `instant()` against `next start` (tests/e2e only).
    exposeTestingApiInProductionBuild: process.env['NEXT_E2E'] === '1',
  },
};

export default config;
