import { env } from "@/env";

export const site = {
  name: "better-supabase",
  tagline:
    "Typed repositories, auth glue, framework adapters and cache helpers for Supabase.",
  url: env.NEXT_PUBLIC_SITE_URL,
  github: "https://github.com/ScaleDockHQ/better-supabase",
  npm: "https://www.npmjs.com/package/better-supabase",
  email: "hello@scaledock.com",
  company: { name: "ScaleDock", url: "https://scaledock.com" },
  install: "pnpm add better-supabase",
  getStarted: "/docs/getting-started",
  docs: "/docs",
} as const;

export type NavLink = {
  readonly href: string;
  readonly label: string;
};

export const navLinks: readonly NavLink[] = [
  { href: "/docs", label: "Docs" },
  { href: "/changelog", label: "Changelog" },
  { href: "/enterprise", label: "Enterprise" },
];

export const footerColumns: readonly {
  readonly title: string;
  readonly links: readonly NavLink[];
}[] = [
  {
    title: "Product",
    links: [
      { href: "/docs/getting-started", label: "Quickstart" },
      { href: "/docs/repository", label: "Repository" },
      { href: "/docs/auth", label: "Auth" },
      { href: "/docs/cli", label: "CLI" },
    ],
  },
  {
    title: "Resources",
    links: [
      { href: "/docs", label: "Docs" },
      { href: "/changelog", label: "Changelog" },
      { href: "/docs/examples", label: "Examples" },
      { href: "/docs/for-ai-agents", label: "For AI agents" },
    ],
  },
  {
    title: "Company",
    links: [
      { href: "/enterprise", label: "Enterprise" },
      { href: site.github, label: "GitHub" },
      { href: site.npm, label: "npm" },
      { href: `mailto:${site.email}`, label: "Contact" },
    ],
  },
];
