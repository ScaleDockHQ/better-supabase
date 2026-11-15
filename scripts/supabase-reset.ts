/**
 * Resets the local database from the migrations and the SQL seeds, then inserts
 * the generated demo rows of the example's entity pages (`pnpm db:seed:pages`,
 * ADR 1032), so a reset leaves the example seeded without a second step.
 * Arguments go to `supabase db reset`. A reset that names `--sql-paths` is a
 * library reset (`pnpm supabase:reset:library`): the example rows are not
 * there, so the page seeds are skipped.
 */
import { spawnSync } from "node:child_process";
import { argv, exit } from "node:process";

export type ResetStep = readonly [command: string, args: readonly string[]];

/** The commands a reset runs, in order. */
export const resetSteps = (args: readonly string[]): readonly ResetStep[] => {
  const reset: ResetStep = ["supabase", ["db", "reset", ...args]];

  return args.some((arg) => arg.startsWith("--sql-paths"))
    ? [reset]
    : [reset, ["node", ["scripts/seed-entity-pages.ts"]]];
};

if (import.meta.main) {
  for (const [command, args] of resetSteps(argv.slice(2))) {
    const result = spawnSync(command, [...args], { stdio: "inherit" });

    if (result.status !== 0) {
      exit(result.status ?? 1);
    }
  }
}
