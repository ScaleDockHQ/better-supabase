import type { Feature } from "./home";

export const pillars: readonly Feature[] = [
  {
    title: "RLS stays in charge",
    body: "defineSupabase holds no secrets. Every request connects with the caller’s client, so Postgres policies decide what each user sees.",
    href: "/docs/auth",
  },
  {
    title: "No service in the data path",
    body: "Everything runs in your code against your Supabase project, hosted or self-hosted. Nothing phones home.",
    href: "/docs/concepts",
  },
  {
    title: "Doctor in CI",
    body: "RLS, index, drift, auth-config and env-file checks plus the Supabase Advisors, reported as SARIF or GitHub annotations.",
    href: "/docs/cli/doctor",
  },
  {
    title: "A small supply chain",
    body: "The core depends only on the Supabase packages and Standard Schema. Advisor lints are fetched at a pinned commit and checked against a SHA-256.",
    href: "/docs/standards",
  },
  {
    title: "Stability you can plan around",
    body: "Semver, an export snapshot reviewed on every change, versioned plugin contracts and a documented deprecation policy.",
    href: "/docs/extending/stability",
  },
  {
    title: "Standards, pinned",
    body: "RFC 9457 problem details, OpenTelemetry, CloudEvents, Standard Webhooks and OpenAPI, with draft specs pinned in code.",
    href: "/docs/standards",
  },
];

export const engagements: readonly {
  readonly title: string;
  readonly body: string;
}[] = [
  {
    title: "Support",
    body: "A direct line to the maintainers for your team, with priority on issues that block you.",
  },
  {
    title: "Architecture reviews",
    body: "RLS policies, auth flows, caching and schema design reviewed against how better-supabase runs them.",
  },
  {
    title: "Migrations",
    body: "Move an existing supabase-js codebase to typed repositories incrementally, one table at a time.",
  },
];
