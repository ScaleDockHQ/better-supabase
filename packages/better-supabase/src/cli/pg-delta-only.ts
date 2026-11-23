import { CliError } from "./core/errors.ts";

/**
 * The message for a feature that only pg-delta has, shown when the project
 * diffs with migra. It names the feature and the two config lines that switch
 * to pg-delta; `db diff` and the doctor keep working under migra.
 */
const pgDeltaOnlyMessage = (feature: string): string =>
  `${feature} needs pg-delta, and this project diffs with migra. Set \`experimental.pgdelta.enabled = true\` and remove \`db.migrations.schema_paths\` in the Supabase config to switch (doctor BS316 explains the change).`;

/** Throws `usage` with `pgDeltaOnlyMessage`. */
export function requirePgDelta(
  feature: string,
  workflow: "pg-delta" | "migra" | "migrations",
): void {
  if (workflow === "migra") {
    throw new CliError("usage", pgDeltaOnlyMessage(feature));
  }
}
