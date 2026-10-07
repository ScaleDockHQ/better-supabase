import type { NextConfig } from "next";

const config: NextConfig = {
  cacheComponents: true,
  // `next build` needs the TypeScript 6 compiler API; the Turbo `typecheck`
  // task runs TypeScript 7 instead.
  typescript: { ignoreBuildErrors: true },
  partialPrefetching: true,
  // `pnpm dev:portless` serves the example at https://example.localhost.
  allowedDevOrigins: ["127.0.0.1", "*.localhost"],
  images: { loader: "custom", loaderFile: "./src/image-loader.ts" },
  experimental: {
    // `pnpm test:e2e` builds with it so `instant()` can hold the navigation;
    // a build without it ignores the lock and every test passes vacuously.
    exposeTestingApiInProductionBuild:
      process.env["EXPOSE_TESTING_API"] === "1",
  },
};

export default config;
