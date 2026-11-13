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

/**
 * Whether the stack's storage service answers. The CLI's native stack starts a
 * service on its first request, so a single 1 s probe reports a service that is
 * still waking up as absent and skips its tests; poll for up to 20 s instead.
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
    } catch {
      // The service is not up yet, or the stack is not running at all.
    }

    await new Promise<void>((resolve) => {
      setTimeout(resolve, 500);
    });
  }

  return false;
}
