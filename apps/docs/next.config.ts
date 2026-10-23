import { withBotId } from "botid/next/config";
import { createMDX } from "fumadocs-mdx/next";

import { createNextConfig } from "@better-supabase/next-config/next-config";

// oxlint-disable-next-line import/no-unassigned-import -- the import validates the environment once, when Next loads the config
import "./env.ts";

const withMDX = createMDX();

// Block pages renamed in 0.15, so links from older guides keep working.
const RENAMED_BLOCK_PAGES = {
  "work-items": "tasks",
  parties: "contacts",
  engagements: "activities",
  targets: "goals",
  "number-sequences": "numbering",
  "shared-signals": "security-events",
  "service-principals": "service-accounts",
  bulk: "bulk-actions",
  controls: "compliance",
  passes: "admission-passes",
  "ai-tasks": "ai-schedules",
  "ai-providers": "ai-keys",
  "workflow-builder": "workflow-editor",
  jobs: "queue",
  flags: "feature-flags",
  access: "permissions",
  rules: "automations",
  identities: "linked-identities",
  activity: "timeline",
} as const satisfies Readonly<Record<string, string>>;

// Plugin pages that moved to their blocks and to the repository section.
const MOVED_PLUGIN_PAGES = {
  timestamps: "blocks/updated-at",
  actor: "blocks/created-by",
  tenant: "blocks/memberships",
  "soft-delete": "blocks/trash",
  validation: "repository/validation",
  rules: "repository/guards",
  lint: "repository/lint",
} as const satisfies Readonly<Record<string, string>>;

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
      {
        source: "/docs/plugins",
        destination: "/docs/extending/plugins",
        permanent: true,
      },
      {
        source: "/docs/repository/expo-sqlite",
        destination: "/docs/repository/sqlite",
        permanent: true,
      },
      ...Object.entries(MOVED_PLUGIN_PAGES).map(([from, to]) => ({
        source: `/docs/plugins/${from}`,
        destination: `/docs/${to}`,
        permanent: true,
      })),
      ...Object.entries(RENAMED_BLOCK_PAGES).map(([from, to]) => ({
        source: `/docs/blocks/${from}`,
        destination: `/docs/blocks/${to}`,
        permanent: true,
      })),
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
