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
    // `@next/playwright`'s `instant()` against `next start` (tests/e2e only).
    exposeTestingApiInProductionBuild: process.env["NEXT_E2E"] === "1",
  },
};

export default config;
