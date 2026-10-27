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
  // `next build` type-checks with the project-local `tsc` (TypeScript 7,
  // `experimental.useTypeScriptCli` is on by default), so this app proves
  // the TypeScript 7 build path the other apps skip.
  typescript: { ignoreBuildErrors: false },
  images: { loader: "custom", loaderFile: "./src/image-loader.ts" },
  // `[locale]` matches every path, so no URL reaches a global not-found page;
  // `[locale]/not-found.tsx` and `api/[...rest]` answer unknown paths.
  experimental: { globalNotFound: false },
});

// Compiles the "use workflow" and "use step" functions and adds the
// /.well-known/workflow routes the World delivers runs to.
export default withWorkflow(withNextIntl(config));
