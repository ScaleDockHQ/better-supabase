export const appName = "better-supabase";
export const docsRoute = "/docs";
export const docsContentRoute = "/llms.mdx/docs";

/** The public Markdown URL of a docs page url: `/docs` is `/docs.md`, `/docs/cli` is `/docs/cli.md`. */
export function markdownUrl(pageUrl: string): string {
  return `${pageUrl.replace(/\/+$/u, "")}.md`;
}

export const gitConfig = {
  user: "ScaleDockHQ",
  repo: "better-supabase",
  branch: "main",
  contentDir: "apps/docs/content/docs",
} as const;
