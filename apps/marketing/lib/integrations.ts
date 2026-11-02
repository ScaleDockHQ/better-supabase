import {
  siAstro,
  siBun,
  siCloudflareworkers,
  siDeno,
  siExpo,
  siExpress,
  siFastify,
  siH3,
  siHono,
  siKoa,
  siModelcontextprotocol,
  siNestjs,
  siNextdotjs,
  siNodedotjs,
  siNuxt,
  siOpentelemetry,
  siReact,
  siReactquery,
  siReactrouter,
  siRedis,
  siSolid,
  siSqlite,
  siStripe,
  siSupabase,
  siSvelte,
  siTanstack,
  siVercel,
  siVuedotjs,
  siZod,
} from "simple-icons";

import type { BrandMark } from "../components/site/brand-icons";

import {
  arktypeGlyph,
  elysiaGlyph,
  orpcGlyph,
  powersyncGlyph,
  valibotGlyph,
  yjsGlyph,
} from "../components/site/brand-icons";

export const integrationGroups = [
  "Server frameworks",
  "Frontend and mobile",
  "Runtimes",
  "Integrations",
] as const;

export type IntegrationGroup = (typeof integrationGroups)[number];

export interface Integration {
  readonly name: string;
  readonly href: string;
  readonly group: IntegrationGroup;
  readonly mark: BrandMark;
}

function group(
  name: IntegrationGroup,
  entries: readonly (readonly [string, string, BrandMark])[],
): Integration[] {
  return entries.map(([title, href, mark]) => ({
    name: title,
    href,
    group: name,
    mark,
  }));
}

/**
 * Every framework, frontend, runtime and SDK better-supabase has a docs page
 * for.
 */
export const integrations: readonly Integration[] = [
  ...group("Server frameworks", [
    ["Next.js", "/docs/frameworks/next", siNextdotjs],
    ["Hono", "/docs/frameworks/hono", siHono],
    ["TanStack Start", "/docs/frameworks/tanstack-start", siTanstack],
    ["React Router", "/docs/frameworks/react-router", siReactrouter],
    ["SvelteKit", "/docs/frameworks/sveltekit", siSvelte],
    ["Nuxt", "/docs/frameworks/nuxt", siNuxt],
    ["Astro", "/docs/frameworks/astro", siAstro],
    ["SolidStart", "/docs/frameworks/solid-start", siSolid],
    ["Elysia", "/docs/frameworks/elysia", elysiaGlyph],
    ["NestJS", "/docs/frameworks/nestjs", siNestjs],
    ["H3", "/docs/frameworks/h3", siH3],
    ["Express", "/docs/frameworks/node", siExpress],
    ["Fastify", "/docs/frameworks/node", siFastify],
    ["Koa", "/docs/frameworks/node", siKoa],
    ["Expo Router", "/docs/frameworks/expo", siExpo],
    ["oRPC", "/docs/frameworks/orpc", orpcGlyph],
    ["MCP", "/docs/frameworks/mcp", siModelcontextprotocol],
    ["WebMCP", "/docs/frameworks/webmcp", siModelcontextprotocol],
  ]),
  ...group("Frontend and mobile", [
    ["React", "/docs/frontend/react", siReact],
    ["React Native", "/docs/frontend/react-native", siExpo],
    ["Vue", "/docs/frontend/vue", siVuedotjs],
    ["Svelte", "/docs/frontend/svelte", siSvelte],
    ["Solid", "/docs/frontend/solid", siSolid],
    ["TanStack Query", "/docs/frontend/query", siReactquery],
    ["TanStack DB", "/docs/frontend/tanstack-db", siTanstack],
  ]),
  ...group("Runtimes", [
    ["Node.js", "/docs/frameworks/node", siNodedotjs],
    ["Deno", "/docs/frameworks/edge", siDeno],
    ["Bun", "/docs/frameworks/edge", siBun],
    ["Cloudflare Workers", "/docs/frameworks/edge", siCloudflareworkers],
    ["Supabase Edge Functions", "/docs/frameworks/edge", siSupabase],
  ]),
  ...group("Integrations", [
    ["AI SDK", "/docs/ai-sdk", siVercel],
    ["Chat SDK", "/docs/chat-sdk", siVercel],
    ["Workflow SDK", "/docs/blocks/workflow-sdk", siVercel],
    ["Flags SDK", "/docs/flags-sdk", siVercel],
    ["PowerSync", "/docs/frontend/powersync", powersyncGlyph],
    ["Expo SQLite", "/docs/frontend/sqlite", siSqlite],
    ["Yjs", "/docs/blocks/documents", yjsGlyph],
    ["Redis streams", "/docs/blocks/streams", siRedis],
    ["Stripe", "/docs/blocks/billing", siStripe],
    ["OpenTelemetry", "/docs/standards/otel", siOpentelemetry],
    ["Zod", "/docs/repository/validation", siZod],
    ["Valibot", "/docs/repository/validation", valibotGlyph],
    ["ArkType", "/docs/repository/validation", arktypeGlyph],
  ]),
];

const GROUP_NOUNS: Record<IntegrationGroup, readonly [string, string]> = {
  "Server frameworks": ["framework", "frameworks"],
  "Frontend and mobile": ["frontend library", "frontend libraries"],
  Runtimes: ["runtime", "runtimes"],
  Integrations: ["integration", "integrations"],
};

export function integrationsIn(name: IntegrationGroup): Integration[] {
  return integrations.filter((integration) => integration.group === name);
}

/** "17 frameworks, 7 frontend libraries, 5 runtimes and 13 integrations". */
export function integrationCounts(): string {
  const parts = integrationGroups.map((name) => {
    const count = integrationsIn(name).length;
    const [one, many] = GROUP_NOUNS[name];

    return `${String(count)} ${count === 1 ? one : many}`;
  });

  const last = parts.pop();

  return `${parts.join(", ")} and ${last ?? ""}`;
}
