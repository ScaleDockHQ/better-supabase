/**
 * Writes `.env.development.local` from the running `supabase start` stack and
 * the Portless URLs, so `pnpm dev:portless` needs no hosted keys.
 */
import { execFileSync } from "node:child_process";
import { writeFile } from "node:fs/promises";

const status = execFileSync(
  "pnpm",
  ["exec", "supabase", "status", "--output", "env"],
  { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] },
);

const stack = new Map<string, string>();
for (const line of status.split("\n")) {
  const match = /^([A-Z0-9_]+)="?(.*?)"?$/.exec(line.trim());
  if (match?.[1] !== undefined && match[2] !== undefined) {
    stack.set(match[1], match[2]);
  }
}

const required = (key: string): string => {
  const value = stack.get(key);
  if (value === undefined) {
    throw new Error(`supabase status has no ${key}; run pnpm supabase:start`);
  }
  return value;
};

const lines = [
  "# Written by pnpm env:local from supabase status. Do not commit.",
  "NEXT_PUBLIC_SITE_URL=https://www.localhost",
  "DOCS_ORIGIN=https://docs.localhost",
  `SUPABASE_URL=${required("API_URL")}`,
  `SUPABASE_DB_URL=${required("DB_URL")}`,
  `SUPABASE_SECRET_KEY=${required("SECRET_KEY")}`,
  "",
];

await writeFile(".env.development.local", lines.join("\n"));
console.log("Wrote .env.development.local");
