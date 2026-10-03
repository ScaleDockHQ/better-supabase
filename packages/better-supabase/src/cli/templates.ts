import { posix } from "node:path";

import type { Framework } from "./project.ts";

export type Integration =
  | "next"
  | "hono"
  | "orpc"
  | "edge"
  | "mcp"
  | "client"
  | "react";

export const INTEGRATIONS: readonly Integration[] = [
  "next",
  "hono",
  "orpc",
  "edge",
  "mcp",
  "client",
  "react",
];

export interface TemplateContext {
  /** `src` or `.`. */
  readonly srcDir: string;
  /** The generated module (`config.output`). */
  readonly generated: string;
  readonly tsExtensions: boolean;
  readonly frameworks: readonly Framework[];
  readonly version: string;
}

export interface TemplateFile {
  readonly path: string;
  readonly contents: string;
}

export interface IntegrationTemplate {
  readonly description: string;
  readonly requires: readonly Integration[];
  readonly packages: readonly string[];
  readonly files: (context: TemplateContext) => TemplateFile[];
  readonly next?: readonly string[];
}

const join = (...parts: string[]): string =>
  posix.normalize(posix.join(...parts));

const libDir = (context: TemplateContext): string =>
  join(context.srcDir, "lib");

/** `lib/supabase/`: the shared definition, `server.ts` and `client.ts`. */
const supabaseDir = (context: TemplateContext): string =>
  join(libDir(context), "supabase");

/** `lib/supabase/index.ts`, imported as `lib/supabase` on both sides. */
export const libEntry = (context: TemplateContext): string =>
  join(supabaseDir(context), "index.ts");

/** Import path of `lib/supabase/index.ts`: the folder, unless the project keeps `.ts` extensions. */
function importLib(context: TemplateContext, from: string): string {
  const path = importFrom(context, from, libEntry(context));
  return context.tsExtensions
    ? path
    : path.replace(/^(\.\.?\/.+)\/index$/, "$1");
}

/** Relative import from one project file to another, following the project's extension style. */
function importFrom(
  context: TemplateContext,
  from: string,
  to: string,
  keepTs: boolean = context.tsExtensions,
): string {
  let path = posix.relative(posix.dirname(from), to);
  if (!path.startsWith(".")) path = `./${path}`;
  return keepTs ? path : path.replace(/\.tsx?$/, "");
}

function publicEnv(context: TemplateContext): { url: string; key: string } {
  const read = (prefix: string, access: "process" | "vite") =>
    access === "vite"
      ? {
          url: `import.meta.env.${prefix}SUPABASE_URL`,
          key: `import.meta.env.${prefix}SUPABASE_PUBLISHABLE_KEY`,
        }
      : {
          url: `process.env.${prefix}SUPABASE_URL!`,
          key: `process.env.${prefix}SUPABASE_PUBLISHABLE_KEY!`,
        };
  if (context.frameworks.includes("next"))
    return read("NEXT_PUBLIC_", "process");
  if (context.frameworks.includes("expo"))
    return read("EXPO_PUBLIC_", "process");
  if (context.frameworks.includes("vite")) return read("VITE_", "vite");
  return read("", "process");
}

const denoJson = (context: TemplateContext): string =>
  `${JSON.stringify(
    {
      imports: {
        "better-supabase": `npm:better-supabase@^${context.version}`,
        "better-supabase/": `npm:/better-supabase@^${context.version}/`,
        "@supabase/supabase-js": "npm:@supabase/supabase-js@^2",
        zod: "npm:zod@^4",
      },
    },
    null,
    2,
  )}\n`;

const SHARED = "supabase/functions/_shared/supabase.ts";

function shared(context: TemplateContext): TemplateFile {
  return {
    path: SHARED,
    contents: `import { defineSupabase } from 'better-supabase';

import { schema } from '${importFrom(context, SHARED, context.generated, true)}';

export const betterSupabase = defineSupabase(schema);
`,
  };
}

/** `supabase/functions/<name>/server.ts`: the function's `bs`. */
function functionServer(
  name: string,
  contents: (shared: string) => string,
): TemplateFile {
  return {
    path: `supabase/functions/${name}/server.ts`,
    contents: contents("../_shared/supabase.ts"),
  };
}

/** Edge Functions import `_shared/supabase.ts`, so they don't need the app definition. */
export const needsLib = (names: readonly Integration[]): boolean =>
  names.length === 0 || names.some((name) => name !== "edge" && name !== "mcp");

/** The files `init` writes: the config and, unless `lib` is false, the isomorphic definition. */
export function baseFiles(
  context: TemplateContext,
  casing: "camel" | "snake",
  lib: boolean = true,
): TemplateFile[] {
  const config: TemplateFile = {
    path: "better-supabase.config.ts",
    contents: `import { defineConfig } from 'better-supabase/config';

export default defineConfig({
  casing: '${casing}',
  output: '${context.generated}',
});
`,
  };
  if (!lib) return [config];
  const path = libEntry(context);
  const generated = importFrom(context, path, context.generated);
  return [
    config,
    {
      path,
      contents: `import { defineSupabase } from 'better-supabase';

import { schema } from '${generated}';

export type { Functions, Models } from '${generated}';

export const betterSupabase = defineSupabase(schema);
`,
    },
  ];
}

export const TEMPLATES: Readonly<Record<Integration, IntegrationTemplate>> = {
  client: {
    description: "Browser client with cookie sessions shared with the server",
    requires: [],
    packages: ["@supabase/ssr"],
    files: (context) => {
      const path = join(supabaseDir(context), "client.ts");
      const env = publicEnv(context);
      return [
        {
          path,
          contents: `import { createClient } from 'better-supabase/client';

import { betterSupabase } from '${importLib(context, path)}';

export const bs = createClient(betterSupabase, {
  env: {
    url: ${env.url},
    publishableKey: ${env.key},
  },
});
`,
        },
      ];
    },
  },
  next: {
    description: "Next.js proxy, Server Components, route handlers and actions",
    requires: ["client"],
    packages: ["@supabase/ssr", "@supabase/server", "server-only"],
    files: (context) => {
      const server = join(supabaseDir(context), "server.ts");
      const proxy = join(context.srcDir, "proxy.ts");
      return [
        {
          path: server,
          contents: `import 'server-only';

import { createNext } from 'better-supabase/next';

import { betterSupabase } from '${importLib(context, server)}';

export const bs = createNext(betterSupabase);
`,
        },
        {
          path: proxy,
          contents: `import type { NextRequest } from 'next/server';

import { bs } from '${importFrom(context, proxy, server)}';

export const proxy = (request: NextRequest) => bs.proxy(request);

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\\\.(?:svg|png|jpg|webp)$).*)'],
};
`,
        },
      ];
    },
    next: [
      "Read the session in Server Components with `const { db } = await bs.context()`.",
    ],
  },
  react: {
    description: "React provider and typed hooks with TanStack Query",
    requires: ["client"],
    packages: ["@tanstack/react-query"],
    files: (context) => {
      const client = join(supabaseDir(context), "client.ts");
      const providers = context.frameworks.includes("next")
        ? join(context.srcDir, "app", "providers.tsx")
        : join(context.srcDir, "providers.tsx");
      const hooks = join(libDir(context), "hooks.ts");
      return [
        {
          path: providers,
          contents: `${context.frameworks.includes("next") ? "'use client';\n\n" : ""}import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { BetterSupabaseProvider } from 'better-supabase/react';
import { type ReactNode, useState } from 'react';

import { bs } from '${importFrom(context, providers, client)}';

export function Providers({ children }: { children: ReactNode }) {
  const [queryClient] = useState(() => new QueryClient());
  return (
    <QueryClientProvider client={queryClient}>
      <BetterSupabaseProvider client={bs} queryClient={queryClient}>
        {children}
      </BetterSupabaseProvider>
    </QueryClientProvider>
  );
}
`,
        },
        {
          path: hooks,
          contents: `import { createHooks } from 'better-supabase/react';

import type { bs } from '${importFrom(context, hooks, client)}';

export const { useDb, useQueries, useAuth, useSupabase } = createHooks<typeof bs>();
`,
        },
      ];
    },
    next: ["Wrap your app in <Providers>."],
  },
  hono: {
    description: "Hono middleware, handlers and REST resources",
    requires: [],
    packages: ["hono", "@supabase/server"],
    files: (context) => {
      const path = join(context.srcDir, "server.ts");
      return [
        {
          path,
          contents: `import { Hono } from 'hono';
import { type HonoEnv, createHono } from 'better-supabase/hono';

import { betterSupabase, type Functions, type Models } from '${importLib(context, path)}';

export const bs = createHono(betterSupabase);

const app = new Hono<HonoEnv<Models, Functions, unknown>>()
  .onError(bs.onError)
  .use('/api/*', bs.middleware())
  .get('/api/me', (c) => c.json({ kind: c.var.auth.kind }));

export default app;
`,
        },
      ];
    },
  },
  orpc: {
    description: "oRPC middleware with typed context and ORPCError mapping",
    requires: [],
    packages: ["@orpc/server", "@supabase/server"],
    files: (context) => {
      const path = join(context.srcDir, "router.ts");
      return [
        {
          path,
          contents: `import { os } from '@orpc/server';
import { createOrpc, type OrpcRequestContext } from 'better-supabase/orpc';

import { betterSupabase } from '${importLib(context, path)}';

export const bs = createOrpc(betterSupabase);

const base = os.$context<OrpcRequestContext>();
const authed = base.use(bs.middleware());

export const router = {
  me: authed.handler(({ context }) => ({ kind: context.auth.kind })),
};
`,
        },
      ];
    },
  },
  edge: {
    description: "A Supabase Edge Function with CORS and Problem Details",
    requires: [],
    packages: [],
    files: (context) => [
      shared(context),
      functionServer(
        "api",
        (shared) => `import { createEdge } from 'better-supabase/edge';

import { betterSupabase } from '${shared}';

export const bs = createEdge(betterSupabase, { cors: true });
`,
      ),
      {
        path: "supabase/functions/api/index.ts",
        contents: `import { bs } from './server.ts';

Deno.serve(bs.handler((_request, { auth }) => ({ kind: auth.kind })));
`,
      },
      { path: "supabase/functions/api/deno.json", contents: denoJson(context) },
    ],
    next: ["Serve it locally with `supabase functions serve api`."],
  },
  mcp: {
    description: "An MCP server (Streamable HTTP) as an Edge Function",
    requires: [],
    packages: [],
    files: (context) => [
      shared(context),
      functionServer(
        "mcp",
        (shared) => `import { createMcp } from 'better-supabase/mcp';

import { betterSupabase } from '${shared}';

export const bs = createMcp(betterSupabase, {
  name: 'app',
  version: '0.1.0',
  resources: {},
});
`,
      ),
      {
        path: "supabase/functions/mcp/index.ts",
        contents: `import { bs } from './server.ts';

Deno.serve(bs.fetch);
`,
      },
      { path: "supabase/functions/mcp/deno.json", contents: denoJson(context) },
    ],
    next: [
      "List tables under `resources` to expose them as tools, e.g. `customers: true`.",
    ],
  },
};

/** The integration and what it requires, dependencies first, without duplicates. */
export function resolveIntegrations(
  names: readonly Integration[],
): Integration[] {
  const ordered: Integration[] = [];
  const visit = (name: Integration): void => {
    if (ordered.includes(name)) return;
    for (const dependency of TEMPLATES[name].requires) visit(dependency);
    ordered.push(name);
  };
  for (const name of names) visit(name);
  return ordered;
}

export function isIntegration(name: string): name is Integration {
  // SAFETY: includes only compares values, so any name is safe to look up.
  return (INTEGRATIONS as readonly string[]).includes(name);
}

/** Integrations `init` adds for the frameworks it finds. */
export function suggestedIntegrations(
  frameworks: readonly Framework[],
): Integration[] {
  const names: Integration[] = [];
  for (const framework of frameworks) {
    switch (framework) {
      case "next":
        names.push("next");
        break;
      case "hono":
        names.push("hono");
        break;
      case "orpc":
        names.push("orpc");
        break;
      case "vite":
      case "expo":
        names.push("client");
        break;
      case "tanstack-query":
        names.push("react");
        break;
      default: {
        const unreachable: never = framework;
        throw new TypeError(`Unknown framework ${String(unreachable)}`);
      }
    }
  }
  return resolveIntegrations(names);
}
