/**
 * Opt-in volume for the local stack. `pnpm db:seed:scale` alone adds 5M audit
 * events and 1M notification recipients to the Acme organization (`--
 * notifications` skips the audit events). `--tier smoke|m|l|xl` adds tenants,
 * customers, notes and the append-only tables at the volume of that tier, in
 * import mode so row triggers do not run (see docs/agents/example-findings.md,
 * EX-011); `--tenants <n>` sets the organizations of a tier, `--clean` removes
 * the rows of an earlier tier first and `--dry-run` prints the batches. Neither
 * `supabase:reset` nor CI runs it. Run it after `pnpm supabase:start`; it reads
 * the database URL that `pnpm env:local` wrote.
 */
import { readFileSync } from "node:fs";
import { argv } from "node:process";
import { Client } from "pg";

import {
  inImportMode,
  parseArgs,
  planSeed,
  renderStep,
  tierSpec,
} from "./seed-scale-plan.ts";

const BATCH = 500_000;
const AUDIT_ROWS = 5_000_000;
const NOTIFICATION_ROWS = 1_000_000;

const url = /^SUPABASE_DB_URL=(.*)$/m.exec(
  readFileSync(".env.development.local", "utf-8"),
)?.[1];

if (!url) {
  throw new Error(
    "Run pnpm supabase:start first: .env.development.local has no SUPABASE_DB_URL.",
  );
}

// The CLI's `db query` prepares one statement; a batch is several (begin, the
// import session, the insert, commit), so this talks to Postgres directly.
const client = new Client({ connectionString: url });

await client.connect();

const run = async (sql: string): Promise<void> => {
  try {
    await client.query(sql);
  } catch (error) {
    // A failed batch leaves its transaction open and aborted.
    await client.query("rollback");

    throw error;
  }
};

const seed = async (file: string, total: number): Promise<void> => {
  const template = readFileSync(`supabase/seeds/scale/${file}`, "utf-8");

  for (let from = 1; from <= total; from += BATCH) {
    const to = Math.min(from + BATCH - 1, total);
    await run(
      template
        .replaceAll("{{from}}", String(from))
        .replaceAll("{{to}}", String(to))
        .replaceAll("{{total}}", String(total)),
    );
    console.log(`${file}: ${to} of ${total}`);
  }
};

const args = parseArgs(argv.slice(2));

const seedTier = async (tier: NonNullable<typeof args.tier>): Promise<void> => {
  const steps = planSeed(tier, args.tenants);
  const spec = tierSpec(tier, args.tenants);

  if (args.dryRun) {
    console.log(
      `tier ${tier}: ${spec.tenants} tenants, ${steps.length} batches`,
    );

    for (const step of steps) {
      console.log(`${step.area}: ${step.file} ${step.from} to ${step.to}`);
    }

    return;
  }

  const sqlDir = "supabase/seeds/scale";

  await run(readFileSync(`${sqlDir}/import-run-start.sql`, "utf-8"));

  try {
    if (args.clean) {
      await run(inImportMode(readFileSync(`${sqlDir}/clean.sql`, "utf-8")));
      console.log("clean: earlier tier rows removed");
    }

    for (const step of steps) {
      const template = readFileSync(`${sqlDir}/${step.file}`, "utf-8");
      await run(inImportMode(renderStep(template, step)));
      console.log(`${step.area}: ${step.to} (${step.file})`);
    }
  } finally {
    await run(readFileSync(`${sqlDir}/import-run-finish.sql`, "utf-8"));
  }

  for (const table of [
    "public.organizations",
    "public.customers",
    "public.notes",
    "better_supabase.audit_events",
    "better_supabase.notification_events",
    "better_supabase.notification_recipients",
  ]) {
    await run(`analyze ${table}`);
  }
};

if (args.tier) {
  await seedTier(args.tier);
} else {
  if (!args.notificationsOnly) {
    await seed("audit-events.sql", AUDIT_ROWS);
  }

  await run(
    "alter table better_supabase.notification_recipients disable trigger user",
  );

  await seed("notification-events.sql", NOTIFICATION_ROWS);

  await run(
    "alter table better_supabase.notification_recipients enable trigger user",
  );

  await run("analyze better_supabase.audit_events");

  await run("analyze better_supabase.notification_events");

  await run("analyze better_supabase.notification_recipients");
}

await client.end();

console.log("Scale seed done.");
