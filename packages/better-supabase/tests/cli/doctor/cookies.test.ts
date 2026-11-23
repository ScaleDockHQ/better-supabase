import { describe, expect, it } from "vitest";

import type { LiveDatabase } from "../../../src/cli/doctor/live.ts";
import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { RULES, runRules } from "../../../src/cli/doctor/rules.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { moduleSnapshotFixture as fixture } from "../fixtures/library.ts";

const base = await parseSnapshot(fixture);

const context = (overrides: Partial<DoctorContext>): DoctorContext => ({
  config: resolveConfig({}, "/project"),
  snapshot: base,
  configToml: undefined,
  envFiles: [],
  gitignore: "",
  sources: [],
  ...overrides,
});

const run = (ctx: DoctorContext) =>
  runRules(
    ctx,
    RULES.filter((rule) => rule.code === "BS644"),
  );

const browser = (encode?: string) => ({
  path: "src/lib/client.ts",
  text: `import { createClient } from "better-supabase/client";\nexport const bsb = createClient(betterSupabase, {\n  env,${encode ? `\n  cookies: { encode: "${encode}" },` : ""}\n});`,
});

const server = {
  path: "src/lib/server.ts",
  text: `import { createNext } from "better-supabase/next";\nexport const bsb = createNext(betterSupabase);`,
};

const reader = {
  path: "src/app/page.ts",
  text: `import { createServerClient } from "@supabase/ssr";\nconst supabase = createServerClient(url, key, { cookies });\nconst { data } = await supabase.auth.getSession();`,
};

const database = (bytes: number | null): LiveDatabase => ({
  describe: "test",
  session: true,
  query: <R>() => Promise.resolve((bytes === null ? [] : [{ bytes }]) as R[]),
});

describe("session cookie carries the user object (BS644)", () => {
  it("stays quiet when either side sets tokens-only or nothing handles the cookie", async () => {
    for (const sources of [
      [],
      [browser("tokens-only"), server],
      [browser("tokens-only")],
      [{ path: "a.ts", text: "const x = 1;" }],
    ]) {
      expect(await run(context({ sources }))).toEqual([]);
    }
  });

  it("names both options and the files that read the cookie session", async () => {
    const findings = await run(
      context({ sources: [browser(), server, reader] }),
    );

    expect(findings).toMatchObject([
      { code: "BS644", severity: "info", target: "session-cookie:encode" },
    ]);
    expect(findings[0]!.message).toContain(
      "`cookies: { encode: 'tokens-only' }` in `createClient`",
    );
    expect(findings[0]!.message).toContain(
      "`auth: { cookie: { encode: 'tokens-only' } }` in the server options",
    );
    expect(findings[0]!.message).toContain(
      "move the user reads in src/app/page.ts:3 from `auth.getSession()`",
    );
  });

  it("adds the bytes of the --as user's object", async () => {
    const [finding] = await run(
      context({
        sources: [browser(), server],
        hookUser: "00000000-0000-4000-8000-0000000000a1",
        database: database(744),
      }),
    );

    expect(finding!.message).toContain(
      "the user object takes about 992 bytes of the cookie",
    );

    const [missing] = await run(
      context({
        sources: [browser(), server],
        hookUser: "00000000-0000-4000-8000-0000000000a1",
        database: database(null),
      }),
    );

    expect(missing!.message).toContain("no such user in auth.users");

    const [skipped] = await run(
      context({
        sources: [browser(), server],
        hookUser: "00000000-0000-4000-8000-0000000000a1",
      }),
    );

    expect(skipped!.message).toContain("was skipped");
  });
});
