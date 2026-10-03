import type { NextConfig } from "next";

type HeaderRules = Awaited<ReturnType<NonNullable<NextConfig["headers"]>>>;

/**
 * Security headers for every document and asset. There is no nonce-based
 * Content-Security-Policy: a nonce forces every page to render per request,
 * which defeats Cache Components.
 */
export const securityHeaders: ReadonlyArray<{ key: string; value: string }> = [
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
 * The shared baseline for the docs and marketing apps. `experimental`,
 * `compiler` and `typescript` merge key by key, and `headers` runs after the
 * security rules so an app can add to them.
 */
export function createNextConfig(overrides: NextConfig = {}): NextConfig {
  const { experimental, typescript, compiler, headers, ...rest } = overrides;
  return {
    reactCompiler: true,
    typedRoutes: true,
    reactStrictMode: true,
    poweredByHeader: false,
    // Portless serves every app at https://<name>.localhost.
    allowedDevOrigins: ["127.0.0.1", "*.localhost"],
    cacheComponents: true,
    partialPrefetching: true,
    cacheLife: {
      reference: { stale: 900, revalidate: 900, expire: 86_400 },
    },
    ...rest,
    compiler: {
      removeConsole:
        process.env.NODE_ENV === "production"
          ? { exclude: ["error", "warn"] }
          : false,
      ...compiler,
    },
    experimental: {
      varyParams: true,
      optimisticRouting: true,
      prefetchInlining: true,
      useOffline: true,
      globalNotFound: true,
      appNewScrollHandler: true,
      requestInsights: true,
      authInterrupts: true,
      typedEnv: true,
      turbopackRustReactCompiler: true,
      serverComponentsHmrCancellation: true,
      exposeTestingApiInProductionBuild:
        process.env["EXPOSE_TESTING_API"] === "1",
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
