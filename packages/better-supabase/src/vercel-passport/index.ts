export {
  PASSPORT_HEADER,
  PASSPORT_ISSUER,
  PASSPORT_JWKS_URL,
  verifyPassport,
  type PassportClaims,
  type PassportPrincipal,
  type PassportResult,
  type PassportTokenSource,
  type VerifyPassportOptions,
} from "./vercel-passport.ts";

export type { JwksStore } from "../core/jwks-cache.ts";

export {
  vercelRuntimeCache,
  type VercelRuntimeCache,
  type VercelRuntimeCacheOptions,
} from "../core/jwks-store.ts";
