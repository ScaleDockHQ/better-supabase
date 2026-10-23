/**
 * The adapter tiers from ADR 0094. Supported adapters get the full test matrix;
 * community adapters get a smoke test in `community-smoke.test.ts` and a note
 * on their docs page. Each entry maps the subpath to its page under
 * `apps/docs/content/docs/frameworks`.
 */
export const SUPPORTED_ADAPTERS = {
  next: "next",
  hono: "hono",
  expo: "expo",
  sveltekit: "sveltekit",
  "tanstack-start": "tanstack-start",
  "react-router": "react-router",
} as const;

export const COMMUNITY_ADAPTERS = {
  astro: "astro",
  edge: "edge",
  elysia: "elysia",
  h3: "h3",
  "h3/v1": "nuxt",
  nestjs: "nestjs",
  node: "node",
  nuxt: "nuxt",
  "solid-start": "solid-start",
} as const;

export type CommunityAdapter = keyof typeof COMMUNITY_ADAPTERS;
