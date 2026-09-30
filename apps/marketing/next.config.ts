import type { NextConfig } from 'next';

const docsOrigin = process.env['DOCS_ORIGIN'] ?? 'http://127.0.0.1:3001';

const docsPaths = [
  '/docs',
  '/docs/:path*',
  '/api/search',
  '/llms.txt',
  '/llms-full.txt',
  '/llms.mdx/:path*',
  '/mcp',
];

const config: NextConfig = {
  reactStrictMode: true,
  // `next build` needs the TypeScript 6 compiler API; the Turbo `typecheck`
  // task runs TypeScript 7 instead.
  typescript: { ignoreBuildErrors: true },
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
