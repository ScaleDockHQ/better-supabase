/** `revoke execute` from everyone, then `grant execute` to `roles`. */
export function grantExecute(
  signature: string,
  roles: readonly string[],
  revokeFrom: readonly string[] = ["public"],
): string {
  return `revoke execute on function ${signature} from ${revokeFrom.join(", ")};\ngrant execute on function ${signature} to ${roles.join(", ")};`;
}

/** `grant <privileges> on <table> to <roles>`. */
export const grantTable = (
  table: string,
  privileges: readonly string[],
  roles: readonly string[],
): string =>
  `grant ${privileges.join(", ")} on ${table} to ${roles.join(", ")};`;
