import type { NextConfig } from 'next';

const docsOrigin = process.env.DOCS_ORIGIN ?? 'http://127.0.0.1:3001';

const docsPaths = [
  '/docs',
  '/docs/:path*',
  '/api/search',
  '/llms.txt',
  '/llms-full.txt',
  '/llms.mdx/:path*',
];

const config: NextConfig = {
  reactStrictMode: true,
  allowedDevOrigins: ['127.0.0.1'],
  redirects() {
    return Promise.resolve([
      {
        source: '/problems/:type',
        destination: '/docs/auth/problems',
        permanent: false,
      },
    ]);
  },
  rewrites() {
    // In production Vercel Services routes these paths to apps/docs.
    if (process.env.NODE_ENV === 'production') {
      return Promise.resolve([]);
    }
    return Promise.resolve(
      docsPaths.map((source) => ({
        source,
        destination: `${docsOrigin}${source}`,
      })),
    );
  },
};

export default config;
