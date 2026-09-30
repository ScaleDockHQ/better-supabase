// Next inlines NEXT_PUBLIC_* only for literal `process.env.NAME` reads, so
// these keys are declared instead of read through the index signature.
declare namespace NodeJS {
  interface ProcessEnv {
    readonly NEXT_PUBLIC_SUPABASE_URL?: string;
    readonly NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?: string;
  }
}
