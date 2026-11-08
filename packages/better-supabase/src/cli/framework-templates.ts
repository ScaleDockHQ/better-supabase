import { posix } from "node:path";

import type {
  FrameworkBinding,
  FrameworkTemplateContext,
  FrameworkTemplateFile,
} from "../plugins/index.ts";

/** `lib/supabase/`, where `init` writes the shared definition. */
const supabaseDir = (context: FrameworkTemplateContext): string =>
  `${context.srcDir === "." ? "" : `${context.srcDir}/`}lib/supabase`;

/** `./index`, or `./index.ts` in a project that keeps its extensions. */
const sibling = (context: FrameworkTemplateContext): string =>
  context.tsExtensions ? "./index.ts" : "./index";

/** The relative import of `lib/supabase/index` from `from`. */
function relative(from: string, context: FrameworkTemplateContext): string {
  const path = posix.relative(
    posix.dirname(from),
    `${supabaseDir(context)}/index`,
  );

  return `${path.startsWith(".") ? path : `./${path}`}${context.tsExtensions ? ".ts" : ""}`;
}

/**
 * `src/hooks.server.ts`: the SvelteKit `handle` hook (`sveltekit` docs page).
 * SvelteKit always keeps its hooks in `src`, so the path doesn't follow
 * `srcDir`, and the import reaches `lib/supabase` relative to it.
 */
function sveltekitTemplates(
  context: FrameworkTemplateContext,
): readonly FrameworkTemplateFile[] {
  return [
    {
      path: "src/hooks.server.ts",
      contents: `import { createServer, withBetterSupabase } from 'better-supabase/server';
import { toSvelteKit } from '${context.serverImport ?? "better-supabase/sveltekit"}';

import { betterSupabase } from '${relative("src/hooks.server.ts", context)}';

const bsb = createServer(betterSupabase);

export const handle = toSvelteKit([
  withBetterSupabase(bsb, { refresh: true, allow: ['user', 'none'] }),
]);
`,
    },
  ];
}

/** `lib/supabase/start-middleware.ts`: the TanStack Start request middleware. */
function tanstackStartTemplates(
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
function reactRouterTemplates(
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

/**
 * The templates of the built-in bindings that write files. They live here, not
 * in the binding, so the `plugins` runtime entry carries no file text (ADR
 * 0582).
 */
const BUILT_IN_TEMPLATES: Readonly<
  Record<
    string,
    (context: FrameworkTemplateContext) => readonly FrameworkTemplateFile[]
  >
> = {
  sveltekit: sveltekitTemplates,
  "tanstack-start": tanstackStartTemplates,
  "react-router": reactRouterTemplates,
};

/** `binding`, with the built-in template of its name when it declares none. */
export function withTemplates(binding: FrameworkBinding): FrameworkBinding {
  const templates = BUILT_IN_TEMPLATES[binding.name];

  return binding.templates === undefined && templates !== undefined
    ? { ...binding, templates }
    : binding;
}
