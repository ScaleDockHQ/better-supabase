import { createNextConfig } from "@better-supabase/next-config/next-config";

import { env } from "./env.ts";

const docsOrigin = env.DOCS_ORIGIN;

const docsPaths = [
  "/docs",
  "/docs/:path*",
  "/api/search",
  "/llms.txt",
  "/llms-full.txt",
  "/llms.mdx/:path*",
  "/mcp",
];

export default createNextConfig({
  experimental: { optimizePackageImports: ["lucide-react"] },
  redirects() {
    return Promise.resolve([
      {
        source: "/problems/:type",
        destination: "/docs/auth/problems",
        permanent: false,
      },
    ]);
  },
  rewrites() {
    // In production Vercel Services routes these paths to apps/docs.
    if (env.NODE_ENV === "production") {
      return Promise.resolve([]);
    }
    return Promise.resolve(
      docsPaths.map((source) => ({
        source,
        destination: `${docsOrigin}${source}`,
      })),
    );
  },
});
