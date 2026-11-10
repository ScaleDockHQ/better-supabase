/**
 * Opt-in volume for the audit and notification reads: 5M audit events and 1M
 * notification recipients in the Acme organization of the local stack. Neither
 * `supabase:reset` nor CI runs it. Run `pnpm db:seed:scale` after `pnpm
 * supabase:start` (`-- notifications` skips the audit events); it reads the
 * database URL that `pnpm env:local` wrote.
 */
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

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

const file = join(mkdtempSync(join(tmpdir(), "seed-scale-")), "batch.sql");

const run = (sql: string): void => {
  writeFileSync(file, sql);
  execFileSync(
    "pnpm",
    [
      "exec",
      "supabase",
      "db",
      "query",
      "--db-url",
      encodeURI(url.includes("sslmode") ? url : `${url}?sslmode=disable`),
      "-f",
      file,
    ],
    { stdio: ["ignore", "pipe", "inherit"] },
  );
};

const seed = (file: string, total: number): void => {
  const template = readFileSync(`supabase/seeds/scale/${file}`, "utf-8");

  for (let from = 1; from <= total; from += BATCH) {
    const to = Math.min(from + BATCH - 1, total);
    run(
      template
        .replaceAll("{{from}}", String(from))
        .replaceAll("{{to}}", String(to)),
    );
    console.log(`${file}: ${to} of ${total}`);
  }
};

const only = process.argv[2];

if (only !== "notifications") {
  seed("audit-events.sql", AUDIT_ROWS);
}

run("alter table better_supabase.notification_recipients disable trigger user");

seed("notification-events.sql", NOTIFICATION_ROWS);

run("alter table better_supabase.notification_recipients enable trigger user");

run("analyze better_supabase.audit_events");

run("analyze better_supabase.notification_events");

run("analyze better_supabase.notification_recipients");

console.log("Scale seed done.");
