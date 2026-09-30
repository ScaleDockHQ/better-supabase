import type { BaseLayoutProps } from "fumadocs-ui/layouts/shared";

import { NavTitle } from "@/components/nav-title";

import { gitConfig } from "./shared";

export function baseOptions(): BaseLayoutProps {
  return {
    nav: { title: NavTitle, url: "/" },
    githubUrl: `https://github.com/${gitConfig.user}/${gitConfig.repo}`,
    links: [
      // Served by the marketing app on the same domain.
      { text: "Changelog", url: "/changelog", external: true },
      { text: "Docs MCP server", url: "/docs/for-ai-agents#docs-mcp-server" },
    ],
  };
}
