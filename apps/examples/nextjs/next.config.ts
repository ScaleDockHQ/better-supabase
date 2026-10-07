import type { NextConfig } from "next";

import createNextIntlPlugin from "next-intl/plugin";

// `next dev` and `next build` extract every `useExtracted` and `getExtracted`
// message into messages/en.po and keep messages/nl.po in step; the app
// imports the .po files directly (src/i18n/request.ts).
const withNextIntl = createNextIntlPlugin({
  experimental: {
    extract: true,
    messages: {
      path: "./messages",
      format: "po",
      locales: "infer",
      sourceLocale: "en",
    },
    srcPath: "./src",
  },
});

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

export default withNextIntl(config);
