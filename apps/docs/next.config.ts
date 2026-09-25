import type { NextConfig } from 'next';

import { createMDX } from 'fumadocs-mdx/next';

const withMDX = createMDX();

const config: NextConfig = {
  reactStrictMode: true,
  // Served under /docs on bettersupabase.com, next to the marketing app.
  assetPrefix: '/docs',
  serverExternalPackages: ['typescript', 'twoslash'],
  redirects() {
    return Promise.resolve([
      { source: '/', destination: '/docs', permanent: false },
    ]);
  },
  rewrites() {
    return Promise.resolve([
      { source: '/docs/_next/:path*', destination: '/_next/:path*' },
    ]);
  },
};

export default withMDX(config);
