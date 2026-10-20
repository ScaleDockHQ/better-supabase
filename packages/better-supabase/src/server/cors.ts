import type { WithCorsConfig } from "@supabase/middleware/cors";

export interface CorsOptions {
  /** Allowed origins, or `*`. Defaults to `*`. */
  readonly origin?: string | readonly string[];
  /** Defaults to the headers supabase-js sends. */
  readonly headers?: readonly string[];
  readonly methods?: readonly string[];
  readonly maxAge?: number;
}

export const SUPABASE_CORS_HEADERS: readonly string[] = [
  "authorization",
  "x-client-info",
  "apikey",
  "content-type",
];

/** `CorsOptions` as `withCors` from `@supabase/middleware/cors` takes them. */
export function corsConfig(cors: CorsOptions): WithCorsConfig {
  return {
    origin:
      cors.origin === undefined || typeof cors.origin === "string"
        ? (cors.origin ?? "*")
        : [...cors.origin],
    allowedHeaders: [...(cors.headers ?? SUPABASE_CORS_HEADERS)],
    methods: [
      ...(cors.methods ?? ["GET", "POST", "PATCH", "DELETE", "OPTIONS"]),
    ],
    ...(cors.maxAge === undefined ? {} : { maxAge: cors.maxAge }),
  };
}
