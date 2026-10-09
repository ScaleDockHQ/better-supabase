// Expo inlines EXPO_PUBLIC_* only for literal `process.env.NAME` reads, so
// these keys are declared instead of read through the index signature.
declare namespace NodeJS {
  interface ProcessEnv {
    readonly EXPO_PUBLIC_SUPABASE_URL: string;
    readonly EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY: string;
    readonly EXPO_PUBLIC_POWERSYNC_URL: string;
    /** The EAS project id; push tokens need it outside Expo Go. */
    readonly EXPO_PUBLIC_EAS_PROJECT_ID?: string;
  }
}
