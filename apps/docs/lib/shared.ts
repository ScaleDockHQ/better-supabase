export const appName = "better-supabase";
export const docsRoute = "/docs";
export const docsContentRoute = "/llms.mdx/docs";

/** The public Markdown URL of a docs page url: `/docs` is `/docs.md`, `/docs/cli` is `/docs/cli.md`. */
export function markdownUrl(pageUrl: string): string {
  return `${pageUrl.replace(/\/+$/u, "")}.md`;
}

/** `/docs/cli/gen`, `cli/gen`, a full URL or a `.md` route, as the page url. */
export function docsUrl(input: string): string {
  const path = input
    .trim()
    .replace(/^https?:\/\/[^/]+/u, "")
    .split(/[?#]/u)[0]!
    .replace(/\.mdx?$/u, "")
    .replace(/\/+$/u, "");

  const parts = path.split("/").filter((part) => part.length > 0);
  const slugs = parts[0] === "docs" ? parts.slice(1) : parts;

  return `${docsRoute}${slugs.length > 0 ? `/${slugs.join("/")}` : ""}`;
}

export const gitConfig = {
  user: "ScaleDockHQ",
  repo: "better-supabase",
  branch: "main",
  contentDir: "apps/docs/content/docs",
} as const;
