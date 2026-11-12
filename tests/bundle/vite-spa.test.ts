import { execFile } from "node:child_process";
import { readdir, readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { promisify } from "node:util";
import { gzipSync } from "node:zlib";
import { expect, test } from "vitest";

const exec = promisify(execFile);
const APP = resolve(import.meta.dirname, "../../apps/examples/vite-react");

/**
 * Gzip of the Vite example's JavaScript, measured with gzip level 9 on
 * 2026-11-09 (`vite build` reported 181.08 kB with its own gzip). Growth of 5%
 * or 256 bytes, whichever is larger, still passes.
 */
const VITE_SPA_GZIP = 178_879;
const TOLERANCE = { ratio: 0.05, bytes: 256 };

async function viteJavaScriptGzip(): Promise<number> {
  await exec("pnpm", ["exec", "vite", "build"], {
    cwd: APP,
    env: { ...process.env, NODE_ENV: "production" },
  });
  const assets = await readdir(join(APP, "dist/assets"));
  let total = 0;

  for (const name of assets) {
    if (!name.endsWith(".js")) {
      continue;
    }

    const code = await readFile(join(APP, "dist/assets", name));

    total += gzipSync(code, { level: 9 }).length;
  }

  return total;
}

test("keeps the Vite SPA within its gzip budget", async () => {
  const gzip = await viteJavaScriptGzip();

  const allowed = Math.max(
    VITE_SPA_GZIP * (1 + TOLERANCE.ratio),
    VITE_SPA_GZIP + TOLERANCE.bytes,
  );

  expect(
    gzip,
    `Vite SPA JavaScript is ${gzip} bytes gzip; the budget is ${VITE_SPA_GZIP}`,
  ).toBeLessThanOrEqual(allowed);
}, 60_000);
