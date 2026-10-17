/**
 * The local stack's URLs. The CLI picks its ports for each checkout or
 * worktree, so `pnpm env:local` writes them to `.env.development.local` and
 * `pnpm test:integration` loads that file; CI exports them from
 * `supabase status`.
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
 * True on the CLI's stack engine (`SUPABASE_RUNTIME` is native, docker or
 * podman). As of CLI 2.121.0 its Realtime denies private channel joins that
 * the legacy stack allows; CI runs those tests on the legacy engine.
 */
export const stackEngine: boolean = ["native", "docker", "podman"].includes(
  process.env["SUPABASE_RUNTIME"] ?? "",
);
