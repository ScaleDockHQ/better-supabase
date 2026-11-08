import type {
  FrameworkTemplateContext,
  FrameworkTemplateFile,
} from "./frameworks.ts";

/** `lib/supabase/`, where `init` writes the shared definition. */
const supabaseDir = (context: FrameworkTemplateContext): string =>
  `${context.srcDir === "." ? "" : `${context.srcDir}/`}lib/supabase`;

/** `./index`, or `./index.ts` in a project that keeps its extensions. */
const sibling = (context: FrameworkTemplateContext): string =>
  context.tsExtensions ? "./index.ts" : "./index";

/**
 * `src/hooks.server.ts`: the SvelteKit `handle` hook (`sveltekit` docs page).
 * SvelteKit always keeps its hooks in `src`, and `$lib` is its own alias, so
 * neither depends on `srcDir`.
 */
export function sveltekitTemplates(
  context: FrameworkTemplateContext,
): readonly FrameworkTemplateFile[] {
  return [
    {
      path: "src/hooks.server.ts",
      contents: `import { createServer, withBetterSupabase } from 'better-supabase/server';
import { toSvelteKit } from '${context.serverImport ?? "better-supabase/sveltekit"}';

import { betterSupabase } from '$lib/supabase';

const bsb = createServer(betterSupabase);

export const handle = toSvelteKit([
  withBetterSupabase(bsb, { refresh: true, allow: ['user', 'none'] }),
]);
`,
    },
  ];
}

/** `lib/supabase/start-middleware.ts`: the TanStack Start request middleware. */
export function tanstackStartTemplates(
  context: FrameworkTemplateContext,
): readonly FrameworkTemplateFile[] {
  return [
    {
      path: `${supabaseDir(context)}/middleware.ts`,
      contents: `import { createMiddleware } from '@tanstack/react-start';
import { createServer, withBetterSupabase } from 'better-supabase/server';
import { toTanStackStart } from '${context.serverImport ?? "better-supabase/tanstack-start"}';

import { betterSupabase } from '${sibling(context)}';

const bsb = createServer(betterSupabase);

// Register it as \`requestMiddleware\` in \`createStart\`, and as a server function
// middleware where a function needs the caller.
export const supabase = createMiddleware().server(
  toTanStackStart([
    withBetterSupabase(bsb, { refresh: true, allow: ['user', 'none'] }),
  ]),
);
`,
    },
  ];
}

/** `lib/supabase/middleware.server.ts`: the React Router server middleware. */
export function reactRouterTemplates(
  context: FrameworkTemplateContext,
): readonly FrameworkTemplateFile[] {
  return [
    {
      path: `${supabaseDir(context)}/middleware.server.ts`,
      contents: `import {
  type BetterSupabaseContributions,
  createServer,
  withBetterSupabase,
} from 'better-supabase/server';
import { createContext } from 'react-router';
import { toReactRouter } from '${context.serverImport ?? "better-supabase/react-router"}';

import { betterSupabase, type Functions, type Models } from '${sibling(context)}';

const bsb = createServer(betterSupabase);

export const supabase =
  createContext<BetterSupabaseContributions<Models, Functions, unknown>>();

// Turn on \`future.v8_middleware\` in react-router.config.ts, then export
// \`middleware = [supabaseMiddleware]\` from app/root.tsx.
export const supabaseMiddleware = toReactRouter(
  [withBetterSupabase(bsb, { refresh: true, allow: ['user', 'none'] })],
  supabase,
);
`,
    },
  ];
}
