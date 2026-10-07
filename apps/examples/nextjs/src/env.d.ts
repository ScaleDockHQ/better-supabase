// Next inlines NEXT_PUBLIC_* only for literal `process.env.NAME` reads, so
// these keys are declared instead of read through the index signature.
declare namespace NodeJS {
  interface ProcessEnv {
    readonly NEXT_PUBLIC_SUPABASE_URL?: string;
    readonly NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?: string;
  }
}

// next-intl's loader turns a catalog into its messages (next.config.ts).
declare module "*.po" {
  import type { AbstractIntlMessages } from "next-intl";

  const messages: AbstractIntlMessages;
  export default messages;
}
