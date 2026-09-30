/** Defaults are the local stack's (`supabase/config.toml`); CI passes the values from `supabase status`. */
export const stack = {
  url: process.env["SUPABASE_URL"] ?? "http://127.0.0.1:55421",
  publishableKey:
    process.env["SUPABASE_PUBLISHABLE_KEY"] ??
    "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH",
  secretKey:
    process.env["SUPABASE_SECRET_KEY"] ??
    "sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz",
};
