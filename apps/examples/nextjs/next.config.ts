import createNextIntlPlugin from "next-intl/plugin";
import { withWorkflow } from "workflow/next";

import { createNextConfig } from "@better-supabase/next-config/next-config";

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

const config = createNextConfig({
  cacheComponents: true,
  // `next build` needs the TypeScript 6 compiler API; the Turbo `typecheck`
  // task runs TypeScript 7 instead.
  typescript: { ignoreBuildErrors: true },
  partialPrefetching: true,
  // Memoizes components and hooks at build time, so the example needs no
  // `useMemo` or `useCallback` by hand.
  reactCompiler: true,
  // `pnpm dev:portless` serves the example at https://example.localhost.
  allowedDevOrigins: ["127.0.0.1", "*.localhost"],
  images: { loader: "custom", loaderFile: "./src/image-loader.ts" },
  // Deferred: the example has no app/global-not-found.tsx, its next-intl
  // Link accepts plain strings, and it reads process.env directly without
  // an app env.ts.
  typedRoutes: false,
  experimental: { globalNotFound: false, typedEnv: false },
});

// Compiles the "use workflow" and "use step" functions and adds the
// /.well-known/workflow routes the World delivers runs to.
export default withWorkflow(withNextIntl(config));
