/**
 * A query parameter of a `/create` URL, decoded; undefined for a name or a
 * code.
 */
export function createUrlParam(
  input: string | undefined,
  name: "authz" | "package",
): string | undefined {
  const value = input?.match(new RegExp(`[?&]${name}=([^&#]*)`))?.[1];

  return value === undefined || value === ""
    ? undefined
    : decodeURIComponent(value);
}

/** What `init` and `apply` print for a URL with `&authz=`. */
export const AUTHZ_NOTE =
  "The authorization library chosen on Create isn't part of the preset. Open Get code on Create for its setup, then set `authorization` in the config to its adapter.";
