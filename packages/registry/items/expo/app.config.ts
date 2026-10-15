import type { ConfigContext, ExpoConfig } from "expo/config";

/**
 * Adds what better-supabase needs on iOS and Android to the config in
 * `app.json`: a URL scheme for the magic-link and OAuth deep links
 * (`handleAuthDeepLink`), secure storage for the session, and push.
 */
export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: config.name ?? "app",
  slug: config.slug ?? "app",
  scheme: config.scheme ?? "app",
  plugins: [
    ...(config.plugins ?? []),
    "expo-secure-store",
    "expo-notifications",
  ],
});
