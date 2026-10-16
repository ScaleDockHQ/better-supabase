/**
 * Writes `.env.development.local` from the running local stack and the
 * Portless URLs, so `pnpm dev:portless` and `pnpm test:integration` need no
 * hosted keys. The CLI picks the stack's ports for each checkout or worktree,
 * so run it again in every worktree.
 */
import { execFileSync } from "node:child_process";
import { writeFile } from "node:fs/promises";
import * as v from "valibot";

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
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
  } catch {
    return undefined;
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

const lines = [
  "# Written by pnpm env:local from supabase status. Do not commit.",
  "NEXT_PUBLIC_SITE_URL=https://www.localhost",
  "DOCS_ORIGIN=https://docs.localhost",
  `SUPABASE_URL=${stack.API_URL}`,
  `SUPABASE_DB_URL=${stack.DB_URL}`,
  `SUPABASE_PUBLISHABLE_KEY=${stack.PUBLISHABLE_KEY}`,
  `SUPABASE_SECRET_KEY=${stack.SECRET_KEY}`,
  `SUPABASE_RUNTIME=${runtime}`,
  `NEXT_PUBLIC_SUPABASE_URL=${stack.API_URL}`,
  `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=${stack.PUBLISHABLE_KEY}`,
  `WORKFLOW_POSTGRES_URL=${stack.DB_URL}`,
  "",
];

await writeFile(".env.development.local", lines.join("\n"));
console.log("Wrote .env.development.local");
