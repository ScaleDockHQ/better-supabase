/**
 * The local stack's URLs. The CLI picks its ports for each checkout or
 * worktree, so `pnpm env:local` writes them to `.env.development.local` and
 * `pnpm test:integration` loads that file; CI exports them from `supabase
 * status`.
 */
function required(key: string): string {
  const value = process.env[key];

  if (value === undefined || value === "") {
    throw new Error(`${key} is not set; run pnpm env:local`);
  }

  return value;
}

export const stackUrl = (): string => required("SUPABASE_URL");

export const stackDbUrl = (): string => required("SUPABASE_DB_URL");

const TLS_CODES = new Set([
  "DEPTH_ZERO_SELF_SIGNED_CERT",
  "SELF_SIGNED_CERT_IN_CHAIN",
  "UNABLE_TO_VERIFY_LEAF_SIGNATURE",
  "UNABLE_TO_GET_ISSUER_CERT_LOCALLY",
  "CERT_HAS_EXPIRED",
  "ERR_TLS_CERT_ALTNAME_INVALID",
]);

/** The TLS error code behind a failed fetch, if there is one. */
export function tlsFailure(error: unknown): string | undefined {
  const cause = error instanceof Error ? error.cause : undefined;

  const code =
    cause instanceof Error && "code" in cause ? String(cause.code) : undefined;

  return code !== undefined && TLS_CODES.has(code) ? code : undefined;
}

/**
 * Whether the stack's storage service answers. The CLI's native stack starts a
 * service on its first request, so a single 1 s probe reports a service that is
 * still waking up as absent and skips its tests; poll for up to 20 s instead. A
 * stack with `[api.tls]` serves HTTPS with its own certificate. A TLS failure
 * throws, because reading it as "unreachable" would skip the tests without a
 * word; point `NODE_EXTRA_CA_CERTS` at the stack's certificate to trust it.
 */
export async function storageReachable(url: string): Promise<boolean> {
  const deadline = Date.now() + 20_000;

  while (Date.now() < deadline) {
    try {
      const response = await fetch(`${url}/storage/v1/status`, {
        signal: AbortSignal.timeout(3000),
      });

      if (response.ok) {
        return true;
      }
    } catch (error) {
      const code = tlsFailure(error);

      if (code !== undefined) {
        throw new Error(
          `${url} failed TLS verification (${code}). Set NODE_EXTRA_CA_CERTS to the stack's certificate.`,
          { cause: error },
        );
      }
      // Otherwise the service is not up yet, or the stack is not running.
    }

    await new Promise<void>((resolve) => {
      setTimeout(resolve, 500);
    });
  }

  return false;
}
