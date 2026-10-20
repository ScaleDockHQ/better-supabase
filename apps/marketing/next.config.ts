import { createNextConfig } from "@better-supabase/next-config/next-config";

import { env } from "./env.ts";

const docsOrigin = env.DOCS_ORIGIN;

const docsPaths = [
  "/docs",
  "/docs.md",
  "/docs/:path*",
  "/api/search",
  "/llms.txt",
  "/llms-full.txt",
  "/llms.mdx/:path*",
  "/mcp",
  // BotID's challenge proxy, which withBotId() rewrites in the docs app.
  "/149e9513-01fa-4fb0-aad4-566afd725d1b/:path*",
];

export default createNextConfig({
  // Vercel Services rewrites `/_next/(.*)` to this service, and the image
  // optimizer returns 404 through that rewrite, so images are served as is.
  images: { unoptimized: true },
  redirects() {
    return Promise.resolve([
      // Create lives in the cloud app. The query string carries the preset
      // and design, so old links and `createUrl()` output keep working.
      {
        source: "/create/:path*",
        destination: "https://app.bettersupabase.com/create/:path*",
        permanent: true,
      },
      {
        source: "/problems/:type",
        destination: "/docs/auth/problems",
        permanent: false,
      },
      {
        source: "/changelog",
        destination: "/docs/changelog",
        permanent: true,
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
