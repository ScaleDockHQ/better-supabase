/**
 * Checks the `apiVersion` of a port an app plugs in (a provider, format, feed
 * or channel). The version is required: a port without `apiVersion: 1` throws
 * at construction, with `label` naming the instance and `kind` the contract.
 */
export function portOf<T extends { readonly apiVersion: 1 }>(
  label: string,
  kind: string,
  port: T,
): T {
  const version: unknown = port.apiVersion;

  if (version !== 1) {
    const noun = kind.split(" ").at(-1) ?? "port";

    throw new TypeError(
      `${label} targets ${kind} API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the ${noun} for API 1.`,
    );
  }

  return port;
}
