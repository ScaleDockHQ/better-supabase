import type { NextConfig } from "next";

import { initialEnv } from "@next/env";

import type { BuildScope } from "./build-scope.ts";

import { isBuildScope } from "./build-scope.ts";

type HeaderRules = Awaited<ReturnType<NonNullable<NextConfig["headers"]>>>;

/**
 * Security headers for every document and asset. There is no nonce-based
 * Content-Security-Policy: a nonce forces every page to render per request,
 * which defeats Cache Components.
 */
export const securityHeaders: readonly { key: string; value: string }[] = [
  {
    key: "Content-Security-Policy",
    value: "base-uri 'self'; frame-ancestors 'none'; object-src 'none'",
  },
  { key: "Cross-Origin-Opener-Policy", value: "same-origin" },
  {
    key: "Permissions-Policy",
    value: "camera=(), geolocation=(), microphone=(), payment=(), usb=()",
  },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  {
    key: "Strict-Transport-Security",
    value: "max-age=63072000; includeSubDomains; preload",
  },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "X-Frame-Options", value: "DENY" },
];

export const documentSecurityHeaderRules: HeaderRules = [
  { source: "/:path*", headers: [...securityHeaders] },
];

/**
 * The prerender scope of this build: `BSB_BUILD_SCOPE` when it is set, else
 * `full` for a Vercel production deployment and `minimal` everywhere else. It
 * reads the shell environment Next saw before loading `.env*` files, because
 * `vercel env pull` writes `VERCEL_ENV` into them.
 */
function resolveBuildScope(
  shell: Readonly<Record<string, string | undefined>> = initialEnv ??
    process.env,
): BuildScope {
  const explicit = shell["BSB_BUILD_SCOPE"];

  if (isBuildScope(explicit)) {
    return explicit;
  }

  return shell["VERCEL_ENV"] === "production" ? "full" : "minimal";
}

/**
 * The shared baseline for the docs and marketing apps. `experimental`,
 * `compiler` and `typescript` merge key by key, and `headers` runs after the
 * security rules so an app can add to them.
 */
export function createNextConfig(overrides: NextConfig = {}): NextConfig {
  const { experimental, typescript, compiler, headers, ...rest } = overrides;
  // GitHub Actions builds are never deployed and never restore .next/cache. Vercel sets CI too,
  // but restores the cache, so it doesn't count here.
  const githubActions = process.env["GITHUB_ACTIONS"] === "true";

  // Next copies config-time env changes into its initial env, so build workers see this too.
  process.env["BSB_BUILD_SCOPE"] = resolveBuildScope();

  return {
    reactCompiler: true,
    enablePrerenderSourceMaps: !githubActions,
    typedRoutes: true,
    reactStrictMode: true,
    poweredByHeader: false,
    // Portless serves every app at https://<name>.localhost.
    allowedDevOrigins: ["127.0.0.1", "*.localhost"],
    cacheComponents: true,
    partialPrefetching: true,
    cacheLife: { reference: { stale: 900, revalidate: 900, expire: 86_400 } },
    ...rest,
    compiler: {
      removeConsole:
        process.env.NODE_ENV === "production"
          ? { exclude: ["error", "warn"] }
          : false,
      ...compiler,
    },
    experimental: {
      useOffline: true,
      globalNotFound: true,
      requestInsights: true,
      authInterrupts: true,
      typedEnv: true,
      optimisticRouting: true,
      // Already the default; set so a default flip in a Next release shows up
      // in this file's diff instead of in navigation request counts.
      prefetchInlining: true,
      instantInsights: { validationLevel: "warning" },
      varyParams: true,
      // Without collection the dev cache grows past 10 GB per app.
      turbopackGc: true,
      // A new git worktree starts from the main checkout's Turbopack cache.
      turbopackSeedCacheFromWorktree: true,
      turbopackRustReactCompiler: true,
      serverComponentsHmrCancellation: true,
      exposeTestingApiInProductionBuild:
        process.env["EXPOSE_TESTING_API"] === "1",
      turbopackFileSystemCacheForBuild: !githubActions,
      ...experimental,
    },
    // The Turbo `typecheck` task gates types; `next build` does not repeat it.
    typescript: { ignoreBuildErrors: true, ...typescript },
    async headers() {
      const own = headers === undefined ? [] : await headers();

      return [...documentSecurityHeaderRules, ...own];
    },
  };
}
