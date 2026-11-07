/**
 * `sql` with the `constraint bsb_<name>` the renderer writes before each check
 * removed, so a test can assert the check itself (ADR 0273).
 */
export const unnamedChecks = (sql: string): string =>
  sql.replaceAll(/constraint bsb_\w+ check \(/g, "check (");
