import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

const SERVERS = [
  "server.ts",
  "server-api.ts",
  "server-core.ts",
  "server-shell.ts",
] as const;

/** The body of `myPermissions`, the loader each server hands the authorizer. */
function loaderOf(file: string): string {
  const source = readFileSync(
    new URL(`../../src/lib/supabase/${file}`, import.meta.url),
    "utf-8",
  );

  const start = source.indexOf("async function myPermissions");

  return source.slice(start);
}

describe("permissions loader (EX-815)", () => {
  // A route handler has no cache scope: `cached()` calls `cacheLife()`, which
  // throws there, and the authorizer reports a throw as a 403 "The authorizer
  // failed". The owner's token is truncated, so every `permission:` route loads.
  it.each(SERVERS)("%s reads my_permissions through context()", (file) => {
    const body = loaderOf(file);

    expect(body).toContain(".context()");
    expect(body).not.toContain(".cached(");
  });
});
