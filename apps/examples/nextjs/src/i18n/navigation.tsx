import type { Route } from "next";
import type { ComponentProps } from "react";

import { createNavigation } from "next-intl/navigation";

import type { AppRoutes } from "../../.next/types/routes";

import { routing } from "./routing";

const navigation = createNavigation(routing);

/** One path segment, with a dynamic `[param]` widened to any string. */
type Segment<S extends string> = S extends `[${string}]` ? string : S;

type Fill<S extends string> = S extends `${infer Head}/${infer Tail}`
  ? `${Segment<Head>}/${Fill<Tail>}`
  : Segment<S>;

/**
 * A page path without the locale prefix. The catch-all `[...rest]` route is
 * left out: it only renders the localized 404, and keeping it would widen the
 * type to every string.
 */
type AppPath<R extends string> = R extends "/[locale]"
  ? "/"
  : R extends `/[locale]/[...${string}]`
    ? never
    : R extends `/[locale]/${infer Rest}`
      ? `/${Fill<Rest>}`
      : never;

/** A page path of the app without the locale prefix and without a query. */
export type AppPathname = AppPath<AppRoutes>;

/** A query string as `URLSearchParams` renders it, with its `?`. */
export type Search = "" | `?${string}`;

/**
 * Every link target of the app, derived from the routes `next typegen` writes
 * to `.next/types/routes.d.ts`. next-intl's `Link` accepts any string, so
 * `typedRoutes` alone never checks a localized link.
 */
export type AppHref =
  | AppPathname
  | `${AppPathname}?${string}`
  | `${AppPathname}#${string}`;

/**
 * Narrows a path that comes from data (a search result, a `next` parameter) to
 * an `AppHref`. Any same-origin path is a valid target because the `[...rest]`
 * route renders the localized 404 for paths with no page.
 */
function isAppHref(value: string): value is AppHref {
  return (
    value.startsWith("/") && !value.startsWith("//") && !value.includes("\\")
  );
}

/**
 * Narrows a locale-prefixed path (from `next/navigation` or a server redirect
 * target) to a typed `Route`, by the same same-origin check.
 */
export function isLocalizedRoute(value: string): value is Route {
  return isAppHref(value);
}

/** A path from data as an `AppHref`, or `fallback` when it is not one. */
export function toAppHref(
  value: string | null | undefined,
  fallback: AppHref = "/",
): AppHref {
  return value !== null && value !== undefined && isAppHref(value)
    ? value
    : fallback;
}

/** `pathname` with a query string from `URLSearchParams` appended. */
export function withSearch(pathname: AppPathname, search: Search): AppHref {
  return search === "" ? pathname : `${pathname}${search}`;
}

/** `search` with its leading `?`, or empty when it has no parameters. */
export function toSearch(params: URLSearchParams): Search {
  const query = params.toString();

  return query === "" ? "" : `?${query}`;
}

/** A route with its query as an object, next-intl's `UrlObject` form. */
export interface AppHrefObject {
  readonly pathname: AppPath<AppRoutes>;
  readonly query?: Readonly<Record<string, string | number | boolean>>;
}

type LinkProps = Omit<ComponentProps<typeof navigation.Link>, "href"> & {
  readonly href: AppHref | AppHrefObject;
};

/** Next-intl's `Link`, with `href` limited to the app's routes. */
export function Link({ href, ...props }: LinkProps) {
  return <navigation.Link href={href} {...props} />;
}

/** Next-intl's `redirect`, with `href` limited to the app's routes. */
export function redirect(
  args: Omit<Parameters<typeof navigation.redirect>[0], "href"> & {
    readonly href: AppHref;
  },
): never {
  return navigation.redirect(args);
}

type RouterOptions = Parameters<
  ReturnType<typeof navigation.useRouter>["push"]
>[1];

export interface AppRouter {
  readonly push: (href: AppHref, options?: RouterOptions) => void;
  readonly replace: (href: AppHref, options?: RouterOptions) => void;
  readonly prefetch: (href: AppHref) => void;
  readonly back: () => void;
  readonly forward: () => void;
  readonly refresh: () => void;
}

/** Next-intl's `useRouter`, with every target limited to the app's routes. */
export function useRouter(): AppRouter {
  return navigation.useRouter();
}

/**
 * The current path without the locale prefix. A pathname never carries a query
 * or hash, so a same-origin path is an `AppPathname`.
 */
export function usePathname(): AppPathname {
  const pathname = navigation.usePathname();

  return isAppPathname(pathname) ? pathname : "/";
}

function isAppPathname(value: string): value is AppPathname {
  return isAppHref(value) && !value.includes("?") && !value.includes("#");
}
