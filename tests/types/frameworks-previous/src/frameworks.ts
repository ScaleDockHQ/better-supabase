// Nuxt 3 adds `options.nitro` in @nuxt/nitro-server; an app's generated
// .nuxt/nuxt.d.ts references it the same way.
/// <reference types="@nuxt/nitro-server" />

/**
 * The framework adapters checked against the previous major of each framework
 * their peer ranges still cover, through the public subpaths an app imports.
 * Each `Fits` fails to compile when the framework's type and the adapter's no
 * longer line up. The current majors are checked in
 * `packages/better-supabase/tests/frameworks.test-d.ts`; SvelteKit declares its
 * types as an ambient module, so two majors can't share one program.
 */

import type {
  Handle,
  HandleServerError,
  LoadEvent,
  RequestEvent,
  error,
  fail,
  redirect,
} from "@sveltejs/kit";
import type { H3V1Handler } from "better-supabase/h3/v1";
import type { BetterSupabaseNuxtModule, NuxtLike } from "better-supabase/nuxt";
import type {
  BetterReactRouter,
  ReactRouterArgs,
  ReactRouterMiddleware,
  ReactRouterOptions,
} from "better-supabase/react-router";
import type {
  BetterSvelteKit,
  SvelteKitDepends,
  SvelteKitHandle,
  SvelteKitHelpers,
  SvelteKitRequestEvent,
} from "better-supabase/sveltekit";
import type { EventHandler, H3Event } from "h3";
import type { Nuxt, NuxtModule } from "nuxt/schema";
import type {
  createContext,
  LoaderFunctionArgs,
  MiddlewareFunction,
} from "react-router";

/** Fails to compile when `From` is not assignable to `To`. */
export type Fits<From extends To, To> = From;

type Kit = BetterSvelteKit<never, never, never>;

/** React Router 7 (7.9 or later, with stable middleware). */
export type ReactRouter7 = [
  Fits<LoaderFunctionArgs, ReactRouterArgs>,
  Fits<
    BetterReactRouter<never, never, never>["middleware"],
    MiddlewareFunction<Response>
  >,
  Fits<ReactRouterMiddleware<unknown, unknown>, MiddlewareFunction<Response>>,
  Fits<typeof createContext, ReactRouterOptions["createContext"]>,
];

/** SvelteKit 2. */
export type SvelteKit2 = [
  Fits<RequestEvent, SvelteKitRequestEvent>,
  Fits<LoadEvent, SvelteKitDepends>,
  Fits<Kit["handle"], Handle>,
  Fits<SvelteKitHandle<object>, Handle>,
  Fits<Kit["handleError"], HandleServerError>,
  Fits<
    { error: typeof error; redirect: typeof redirect; fail: typeof fail },
    SvelteKitHelpers
  >,
];

/** H3 1, which Nitro 2 and Nuxt 3 and 4 run. */
export type H3V1 = [
  Fits<H3Event, Parameters<H3V1Handler<object>>[0]>,
  Fits<H3V1Handler<object>, EventHandler>,
];

/** Nuxt 3. */
export type Nuxt3 = [
  Fits<Nuxt, NuxtLike>,
  Fits<BetterSupabaseNuxtModule, NuxtModule>,
];
