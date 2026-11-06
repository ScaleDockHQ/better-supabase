/** What `createPolicy` writes. Names and tables arrive quoted. */
export interface PolicyStatement {
  readonly name: string;
  readonly table: string;
  readonly permissive: boolean;
  readonly command: string;
  readonly roles: readonly string[];
  readonly using: string | null;
  readonly check: string | null;
}

/**
 * The `create policy` statement in the layout the block modules use: the header
 * on one line, then `for`, `using` and `with check` on their own lines, ending
 * with a semicolon. It never drops: a schema diff removes a policy the files no
 * longer declare.
 */
export function createPolicy(policy: PolicyStatement): string {
  const lines = [
    `create policy ${policy.name} on ${policy.table}${policy.permissive ? "" : " as restrictive"}`,
    `  for ${policy.command} to ${policy.roles.join(", ")}`,
  ];

  if (policy.using !== null) {
    lines.push(`  using (${policy.using})`);
  }

  if (policy.check !== null) {
    lines.push(`  with check (${policy.check})`);
  }

  return `${lines.join("\n")};`;
}
