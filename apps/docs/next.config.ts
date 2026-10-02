import { withBotId } from "botid/next/config";
import { createMDX } from "fumadocs-mdx/next";

import { createNextConfig } from "@better-supabase/next-config/next-config";

// oxlint-disable-next-line import/no-unassigned-import -- the import validates the environment once, when Next loads the config
import "./env.ts";

const withMDX = createMDX();

const config = createNextConfig({
  // Served under /docs on bettersupabase.com, next to the marketing app.
  assetPrefix: "/docs",
  serverExternalPackages: ["typescript", "twoslash"],
  experimental: { optimizePackageImports: ["lucide-react"] },
  redirects() {
    return Promise.resolve([
      { source: "/", destination: "/docs", permanent: false },
    ]);
  },
  rewrites() {
    return Promise.resolve([
      { source: "/docs/_next/:path*", destination: "/_next/:path*" },
    ]);
  },
});

export default withBotId(withMDX(config));
