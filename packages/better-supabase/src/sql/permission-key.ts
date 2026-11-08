/**
 * A block's default permission key under a provider: `own` (`<block>.<action>`)
 * while the provider's `catalog` lists it or is unknown, else `<primary
 * entity>.<action>` when the provider lists that key instead.
 */
export function resourcePermissionKey(
  own: string,
  action: string,
  primaryNoun: string | undefined,
  catalog: readonly string[] | undefined,
  keyOf: (key: string) => string,
): string {
  if (
    catalog === undefined ||
    catalog.includes(own) ||
    primaryNoun === undefined
  ) {
    return own;
  }

  const resource = keyOf(`${primaryNoun}.${action}`);

  return catalog.includes(resource) ? resource : own;
}
