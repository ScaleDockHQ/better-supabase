// The env keys the items read. Next and Expo inline public keys only for
// literal `process.env.NAME` reads, so the items never use the index signature.
declare namespace NodeJS {
  interface ProcessEnv {
    readonly NEXT_PUBLIC_SUPABASE_URL?: string;
    readonly NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?: string;
    readonly EXPO_PUBLIC_SUPABASE_URL?: string;
    readonly EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY?: string;
    readonly EXPO_PUBLIC_EAS_PROJECT_ID?: string;
    readonly APP_URL?: string;
    readonly CRON_SECRET?: string;
    readonly STRIPE_SECRET_KEY?: string;
    readonly STRIPE_WEBHOOK_SECRET?: string;
  }
}
