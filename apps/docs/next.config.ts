import { withBotId } from "botid/next/config";
import { createMDX } from "fumadocs-mdx/next";

import { createNextConfig } from "@better-supabase/next-config/next-config";

// oxlint-disable-next-line import/no-unassigned-import -- the import validates the environment once, when Next loads the config
import "./env.ts";

const withMDX = createMDX();

/** A client that asks for Markdown (`Accept: text/markdown`) gets the `.md` route. */
const prefersMarkdown = [
  { type: "header", key: "accept", value: "(.*)text/markdown(.*)" },
] as const;

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
    ]);
  },
  rewrites() {
    return Promise.resolve({
      beforeFiles: [
        { source: "/docs/_next/:path*", destination: "/_next/:path*" },
        { source: "/docs.md", destination: "/llms.mdx/docs/content.md" },
        {
          source: "/docs/:path(.*)\\.md",
          destination: "/llms.mdx/docs/:path/content.md",
        },
        {
          source: "/docs",
          has: [...prefersMarkdown],
          destination: "/llms.mdx/docs/content.md",
        },
        {
          source: "/docs/:path*",
          has: [...prefersMarkdown],
          destination: "/llms.mdx/docs/:path*/content.md",
        },
      ],
      afterFiles: [],
      fallback: [],
    });
  },
  headers() {
    return Promise.resolve([
      // The same URL answers HTML or Markdown, so caches key on Accept.
      { source: "/docs/:path*", headers: [{ key: "Vary", value: "Accept" }] },
      { source: "/docs", headers: [{ key: "Vary", value: "Accept" }] },
    ]);
  },
});

export default withBotId(withMDX(config));
