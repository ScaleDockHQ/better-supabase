/**
 * Starts the Next.js example behind Portless from this shell instead of from
 * inside a Turbo session. Turbo hands a task a pipe that closes when its
 * session ends, and a dev server writing to a closed pipe loops on `EPIPE` at
 * 100 percent CPU (EX-309, EX-704). It builds the example's dependencies
 * through Turbo first, seeds the entity pages, then gives the dev server this
 * process's own stdio.
 */
import { spawn, spawnSync } from "node:child_process";
import process from "node:process";

const EXAMPLE = "@better-supabase/example-nextjs";

const build = spawnSync(
  "pnpm",
  ["exec", "turbo", "run", "build", `--filter=${EXAMPLE}^...`],
  { stdio: "inherit" },
);

if (build.status !== 0) {
  process.exit(build.status ?? 1);
}

// Inserts the demo rows of the entity pages; a second run adds nothing, and a
// missing stack must not stop the dev server (ADR 1032).
const seeded = spawnSync("node", ["scripts/seed-entity-pages.ts"], {
  stdio: "inherit",
});

if (seeded.status !== 0) {
  console.warn(
    "The entity pages were not seeded; run `pnpm supabase:start` and `pnpm db:seed:pages`.",
  );
}

const dev = spawn("pnpm", ["--filter", EXAMPLE, "dev:portless"], {
  stdio: "inherit",
});

for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"] as const) {
  process.on(signal, () => {
    dev.kill(signal);
  });
}

dev.on("exit", (code, signal) => {
  if (signal === null) {
    process.exit(code ?? 0);
  }

  process.kill(process.pid, signal);
});
