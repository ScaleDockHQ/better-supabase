// `experimental.typedEnv` writes these types only during `next dev`, so the
// keys `src/env.ts` reads with a literal `process.env.NAME` are declared here
// for `tsc` in CI too.
declare namespace NodeJS {
  interface ProcessEnv {
    readonly NEXT_PUBLIC_SUPABASE_URL?: string;
    readonly NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?: string;
    readonly NEXT_PUBLIC_VAPID_PUBLIC_KEY?: string;
  }
}

// next-intl's loader turns a catalog into its messages (next.config.ts).
declare module "*.po" {
  import type { AbstractIntlMessages } from "next-intl";

  const messages: AbstractIntlMessages;
  export default messages;
}
