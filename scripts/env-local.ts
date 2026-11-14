/**
 * Writes `.env.development.local` from the running local stack and the Portless
 * URLs, so `pnpm dev:portless` and `pnpm test:integration` need no hosted keys.
 * The CLI picks the stack's ports for each checkout or worktree, and Portless
 * prefixes the hosts with a linked worktree's branch, so run it again in every
 * worktree.
 */
import { execFileSync } from "node:child_process";
import { access, readFile, writeFile } from "node:fs/promises";
import * as v from "valibot";

import { publicJwks } from "./public-jwks.ts";

const Stack = v.looseObject({
  API_URL: v.pipe(v.string(), v.url()),
  DB_URL: v.pipe(v.string(), v.minLength(1)),
  PUBLISHABLE_KEY: v.pipe(v.string(), v.minLength(1)),
  SECRET_KEY: v.pipe(v.string(), v.minLength(1)),
});

const Runtime = v.looseObject({ runtime: v.string() });

const supabase = (...args: string[]): string | undefined => {
  try {
    return execFileSync("pnpm", ["exec", "supabase", ...args], {
      encoding: "utf-8",
      stdio: ["ignore", "pipe", "ignore"],
    });
  } catch {
    return undefined;
  }
};

/**
 * The app's Portless URL in this checkout, such as
 * `https://fix-ui.www.localhost`.
 */
const portlessUrl = (name: string): string => {
  try {
    return execFileSync("pnpm", ["exec", "portless", "get", name], {
      encoding: "utf-8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return `https://${name}.localhost`;
  }
};

const parse = <S extends v.GenericSchema>(
  schema: S,
  stdout: string,
): v.InferOutput<S> =>
  v.parse(schema, JSON.parse(stdout.slice(Math.max(stdout.indexOf("{"), 0))));

// The stack engine prints the keys with `--env`; the legacy engine
// (SUPABASE_EXPERIMENTAL_STACK=0) only knows `-o json`.
const engine = supabase("status", "--env", "--output-format", "json");
const status = engine ?? supabase("status", "-o", "json");

if (status === undefined) {
  throw new Error("supabase status failed; run pnpm supabase:start");
}

const stack = parse(Stack, status);
const details = engine && supabase("status", "--output-format", "json");
const runtime = details ? parse(Runtime, details).runtime : "legacy";

// The server verifies tokens from these keys without a request to the Auth
// server. A stack started without the file has no inline keys.
const jwks = await readFile("supabase/signing_keys.json", "utf-8").then(
  (text) => publicJwks(text),
  () => undefined,
);

const lines = [
  "# Written by pnpm env:local from supabase status. Do not commit.",
  `NEXT_PUBLIC_SITE_URL=${portlessUrl("www")}`,
  `DOCS_ORIGIN=${portlessUrl("docs")}`,
  `SUPABASE_URL=${stack.API_URL}`,
  `SUPABASE_DB_URL=${stack.DB_URL}`,
  `SUPABASE_PUBLISHABLE_KEY=${stack.PUBLISHABLE_KEY}`,
  `SUPABASE_SECRET_KEY=${stack.SECRET_KEY}`,
  `SUPABASE_RUNTIME=${runtime}`,
  `NEXT_PUBLIC_SUPABASE_URL=${stack.API_URL}`,
  `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=${stack.PUBLISHABLE_KEY}`,
  `WORKFLOW_POSTGRES_URL=${stack.DB_URL}`,
  // Without the world a workflow run starts and never writes a row (EX-207).
  "WORKFLOW_TARGET_WORLD=better-supabase/workflow-sdk/world",
  ...(jwks === undefined ? [] : [`SUPABASE_JWKS=${jwks}`]),
  "",
];

await writeFile(".env.development.local", lines.join("\n"));

console.log("Wrote .env.development.local");

// The example app loads its own copy before the root file. A copy that names
// an earlier stack's ports sends the first signed-in page into an error loop
// (EX-922), so a copy that exists follows the stack too.
const APP_COPY = "apps/examples/nextjs/.env.development.local";

const hasAppCopy = await access(APP_COPY).then(
  () => true,
  () => false,
);

if (hasAppCopy) {
  await writeFile(APP_COPY, lines.join("\n"));
  console.log(`Wrote ${APP_COPY}`);
}
