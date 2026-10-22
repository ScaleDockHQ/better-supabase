import { withBotId } from "botid/next/config";
import { createMDX } from "fumadocs-mdx/next";

import { createNextConfig } from "@better-supabase/next-config/next-config";

// oxlint-disable-next-line import/no-unassigned-import -- the import validates the environment once, when Next loads the config
import "./env.ts";

const withMDX = createMDX();

const config = createNextConfig({
  // Served under /docs on bettersupabase.com, next to the marketing app.
  assetPrefix: "/docs",
  redirects() {
    return Promise.resolve([
      { source: "/", destination: "/docs", permanent: false },
      {
        source: "/docs/kits/:slug(list|storage|realtime)",
        destination: "/docs/platform/:slug",
        permanent: true,
      },
      {
        source: "/docs/kits/orgs",
        destination: "/docs/blocks/organizations",
        permanent: true,
      },
      { source: "/docs/kits", destination: "/docs/blocks", permanent: true },
      {
        source: "/docs/kits/:slug",
        destination: "/docs/blocks/:slug",
        permanent: true,
      },
      {
        source: "/docs/cli/local",
        destination: "/docs/cli/dev",
        permanent: true,
      },
      {
        source: "/docs/cli/stack",
        destination: "/docs/cli/dev",
        permanent: true,
      },
      {
        source: "/docs/presets/codes",
        destination: "/docs/presets/designs",
        permanent: true,
      },
      {
        source: "/docs/cli/introspect",
        destination: "/docs/cli/gen",
        permanent: true,
      },
    ]);
  },
  rewrites() {
    return Promise.resolve({
      beforeFiles: [
        { source: "/docs/_next/:path*", destination: "/_next/:path*" },
        { source: "/docs/llms.txt", destination: "/llms.txt" },
        { source: "/docs/llms-full.txt", destination: "/llms-full.txt" },
        { source: "/docs.md", destination: "/llms.mdx/docs/content.md" },
        {
          source: "/docs/:path(.*)\\.md",
          destination: "/llms.mdx/docs/:path/content.md",
        },
      ],
      afterFiles: [],
      fallback: [],
    });
  },
});

export default withBotId(withMDX(config));
