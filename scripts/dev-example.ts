/**
 * Starts the Next.js example behind Portless from this shell instead of from
 * inside a Turbo session. Turbo hands a task a pipe that closes when its
 * session ends, and a dev server writing to a closed pipe loops on `EPIPE` at
 * 100 percent CPU (EX-309, EX-704). It builds the example's dependencies
 * through Turbo first, then gives the dev server this process's own stdio.
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
