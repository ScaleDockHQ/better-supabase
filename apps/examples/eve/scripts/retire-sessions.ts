import { endStrandedSessions } from "better-supabase/eve";
import { createSupabaseWorld } from "better-supabase/workflow-sdk/world";

// Run `pnpm retire:sessions <eve-version>` before you deploy an eve version
// that cannot resume the sessions the old one started. `--apply` ends them;
// without it the script only lists them. It then purges old runs and keeps the
// ones the session sync has not read yet.
const version = process.argv[2];

if (version === undefined) {
  throw new Error("Usage: pnpm retire:sessions <eve-version> [--apply]");
}

const apply = process.argv.includes("--apply");
const world = createSupabaseWorld();

const result = await endStrandedSessions({
  store: world.eveSessions,
  notVersion: version,
  dryRun: !apply,
});

console.log(
  `${apply ? `Ended ${result.ended}` : `Would end ${result.sessions.length}`} session(s) not on eve ${version}.`,
);

if (apply) {
  await world.purgeRuns({ olderThan: "30 days", skipUnprojected: true });
}

await world.close();
