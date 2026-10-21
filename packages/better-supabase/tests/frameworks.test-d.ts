import type { FetchEvent } from "@solidjs/start/server";
import type { LoadEvent, RequestEvent } from "@sveltejs/kit";
import type { Handle, HandleServerError } from "@sveltejs/kit/hooks";
import type {
  APIContext,
  ExternalImageService,
  MiddlewareHandler,
} from "astro";
import type Koa from "koa";
import type { Nuxt, NuxtModule } from "nuxt/schema";
import type {
  createContext,
  LoaderFunctionArgs,
  MiddlewareFunction,
} from "react-router";

import { createMiddleware as createSolidMiddleware } from "@solidjs/start/middleware";
import { error, fail, redirect } from "@sveltejs/kit";
import { createMiddleware as createStartMiddleware } from "@tanstack/react-start";
import { Elysia } from "elysia";
import express from "express";
import Fastify from "fastify";
import { H3, type H3Event as H3EventV2 } from "h3";
import { describe, expectTypeOf, it } from "vitest";

import type {
  AstroContextLike,
  AstroImageService,
  BetterAstro,
} from "../src/astro/index.ts";
import type { ElysiaBridge } from "../src/elysia/index.ts";
import type { H3Middleware } from "../src/h3/index.ts";
import type {
  ExpressErrorHandler,
  ExpressMiddleware,
  FastifyHook,
  KoaMiddleware,
} from "../src/node/index.ts";
import type { BetterSupabaseNuxtModule, NuxtLike } from "../src/nuxt/index.ts";
import type {
  BetterReactRouter,
  ReactRouterArgs,
  ReactRouterOptions,
} from "../src/react-router/create.ts";
import type { SolidFetchEvent } from "../src/solid-start/index.ts";
import type {
  BetterSvelteKit,
  SvelteKitDepends,
  SvelteKitHelpers,
  SvelteKitRequestEvent,
} from "../src/sveltekit/create.ts";
import type { BetterTanStackStart } from "../src/tanstack-start/create.ts";

/**
 * The structural framework types the adapters declare, checked against the
 * frameworks' real types at the pinned versions, in both directions: what
 * the framework passes fits what the adapter reads, and what the adapter
 * returns fits where the framework takes it. A major release that breaks
 * one fails here; the previous majors still in the
 * peer ranges are checked in `tests/types/frameworks-previous`.
 */
describe("framework adapters", () => {
  it("React Router runs the middleware and pass loader arguments", () => {
    type Middleware = BetterReactRouter<never, never, never>["middleware"];

    expectTypeOf<LoaderFunctionArgs>().toExtend<ReactRouterArgs>();
    expectTypeOf<Middleware>().toExtend<MiddlewareFunction<Response>>();
    expectTypeOf<typeof createContext>().toExtend<
      ReactRouterOptions["createContext"]
    >();
  });

  it("SvelteKit runs the handle hook, actions and error handler", () => {
    type Kit = BetterSvelteKit<never, never, never>;

    expectTypeOf<RequestEvent>().toExtend<SvelteKitRequestEvent>();
    expectTypeOf<LoadEvent>().toExtend<SvelteKitDepends>();
    expectTypeOf<Kit["handle"]>().toExtend<Handle>();
    expectTypeOf<Kit["handleError"]>().toExtend<HandleServerError>();
    // oxlint-disable-next-line typescript/no-deprecated -- one finding: the lint flags `error` itself because one overload is deprecated; the adapter calls the `(status, message)` one.
    const helpers: SvelteKitHelpers = { error, redirect, fail };
    expectTypeOf(helpers).toExtend<SvelteKitHelpers>();
  });

  it("Astro runs onRequest and the image service", () => {
    expectTypeOf<APIContext>().toExtend<AstroContextLike>();
    expectTypeOf<
      BetterAstro<never, never, never>["onRequest"]
    >().toExtend<MiddlewareHandler>();
    expectTypeOf<AstroImageService>().toExtend<
      Pick<ExternalImageService, "getURL">
    >();
  });

  it("SolidStart takes the middleware and passes its FetchEvent", () => {
    expectTypeOf<FetchEvent>().toExtend<SolidFetchEvent>();
    createSolidMiddleware({});
  });

  it("TanStack Start takes the request middleware", () => {
    createStartMiddleware().server(
      {} as BetterTanStackStart<never, never, never>["middleware"],
    );
  });

  it("H3 takes the middleware", () => {
    expectTypeOf<H3EventV2>().toExtend<Parameters<H3Middleware<object>>[0]>();
    new H3().use({} as H3Middleware<object>);
  });

  it("Nuxt installs the module", () => {
    expectTypeOf<Nuxt>().toExtend<NuxtLike>();
    expectTypeOf<BetterSupabaseNuxtModule>().toExtend<NuxtModule>();
  });

  it("Elysia serves through the bridge and derives its context", () => {
    const bridge = {} as ElysiaBridge<[]>;
    const app = new Elysia().derive(({ request }) => bridge.context(request));
    bridge.wrap((request) => app.handle(request));
  });

  it("Express, Fastify and Koa mount the middleware", () => {
    express()
      .use({} as ExpressMiddleware)
      .use({} as ExpressErrorHandler);

    Fastify()
      .addHook("onRequest", {} as FastifyHook)
      .addHook("preHandler", {} as FastifyHook);

    ({} as Koa).use({} as KoaMiddleware);
  });
});
