import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import {
  chmod,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { mergeEnv } from "../../src/cli/commands/env.ts";
import { loadSkills } from "../../src/cli/commands/skills.ts";
import { run } from "../../src/cli/run.ts";
import {
  baseFiles,
  INTEGRATIONS,
  resolveIntegrations,
  type TemplateContext,
  TEMPLATES,
} from "../../src/cli/templates.ts";

const packageRoot = fileURLToPath(new URL("../../", import.meta.url));
const src = join(packageRoot, "src");

let dir: string;

beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), "better-supabase-dx-"));
});

afterEach(async () => {
  await rm(dir, { recursive: true, force: true });
});

async function project(
  dependencies: Record<string, string>,
  extra: Record<string, string> = {},
): Promise<void> {
  await writeFile(
    join(dir, "package.json"),
    JSON.stringify({ name: "app", dependencies }),
  );
  await writeFile(join(dir, "pnpm-lock.yaml"), "");
  for (const [path, contents] of Object.entries(extra)) {
    await mkdir(dirname(join(dir, path)), { recursive: true });
    await writeFile(join(dir, path), contents);
  }
}

describe("init and add", () => {
  it("detects the framework, writes glue and keeps existing files", async () => {
    await project(
      { next: "16.0.0", "@tanstack/react-query": "5.0.0", pg: "8" },
      { "src/.keep": "" },
    );
    const init = await run(["init", "--cwd", dir]);
    expect(init.code).toBe(0);
    expect(init.stdout).toContain("Found next, tanstack-query.");
    for (const path of [
      "better-supabase.config.ts",
      "src/lib/supabase.ts",
      "src/lib/supabase.browser.ts",
      "src/lib/supabase.server.ts",
      "src/proxy.ts",
      "src/app/providers.tsx",
      "src/lib/hooks.ts",
    ]) {
      expect({ path, exists: existsSync(join(dir, path)) }).toEqual({
        path,
        exists: true,
      });
    }
    expect(await readFile(join(dir, "src/lib/supabase.ts"), "utf8")).toContain(
      "from './supabase/generated'",
    );
    expect(
      await readFile(join(dir, "src/lib/supabase.browser.ts"), "utf8"),
    ).toContain("process.env.NEXT_PUBLIC_SUPABASE_URL!");
    expect(init.stdout).toContain(
      "pnpm add better-supabase @supabase/supabase-js @supabase/ssr",
    );
    expect(init.stdout).not.toContain("pnpm add -D pg");

    await writeFile(join(dir, "src/proxy.ts"), "// mine\n");
    await rm(join(dir, "better-supabase.config.ts"));
    await writeFile(
      join(dir, "better-supabase.config.json"),
      '{"output": "src/db/generated.ts"}',
    );
    const again = await run(["init", "--cwd", dir]);
    expect(again.stderr).toBe("");
    expect(again.stdout).toContain("Kept    src/proxy.ts (exists)");
    expect(await readFile(join(dir, "src/proxy.ts"), "utf8")).toBe("// mine\n");
  });

  it("adds integrations with their dependencies", async () => {
    await project({ hono: "4" });
    const add = await run(["add", "mcp", "orpc", "--cwd", dir, "--dry-run"]);
    expect(add.code).toBe(0);
    expect(add.stdout).toContain("Would write supabase/functions/mcp/index.ts");
    expect(add.stdout).toContain("Would write router.ts");
    expect(add.stdout).toContain("pnpm add @orpc/server @supabase/server");
    expect(existsSync(join(dir, "router.ts"))).toBe(false);
    expect((await run(["add", "nope", "--cwd", dir])).code).toBe(2);
    expect(resolveIntegrations(["react"])).toEqual(["client", "react"]);
  });

  it("skips the app definition for Edge Function projects", async () => {
    await project({});
    const init = await run(["init", "--with", "mcp", "--cwd", dir]);
    expect(init.code).toBe(0);
    expect(
      existsSync(join(dir, "supabase/functions/_shared/supabase.ts")),
    ).toBe(true);
    expect(existsSync(join(dir, "lib/supabase.ts"))).toBe(false);
  });

  it("prints command help", async () => {
    const help = await run(["add", "--help"]);
    expect(help.stdout).toContain("Usage: better-supabase add");
    for (const name of INTEGRATIONS) expect(help.stdout).toContain(name);
  });
});

describe("templates", () => {
  it("typecheck against the library", async () => {
    const root = join(packageRoot, "tmp", `templates-${process.pid}`);
    await rm(root, { recursive: true, force: true });
    const context: TemplateContext = {
      srcDir: "src",
      generated: "src/lib/supabase/generated.ts",
      tsExtensions: false,
      frameworks: ["next", "tanstack-query", "hono", "orpc"],
      version: "0.0.0",
    };
    const files = [
      ...baseFiles(context, "camel").filter(
        (file) =>
          file.path.endsWith(".ts") && !file.path.startsWith("better-supabase"),
      ),
      ...INTEGRATIONS.flatMap((name) => TEMPLATES[name].files(context)),
    ];
    const generated = (
      await readFile(
        join(packageRoot, "tests/fixtures/generated-camel.ts"),
        "utf8",
      )
    ).replaceAll('"../../src/index.ts"', '"better-supabase"');
    const databaseTypes = await readFile(
      join(packageRoot, "tests/fixtures/database.types.ts"),
      "utf8",
    );
    try {
      for (const file of [
        ...files,
        { path: context.generated, contents: generated },
        {
          path: context.generated.replace(/[^/]+$/, "database.types.ts"),
          contents: databaseTypes,
        },
        {
          path: "deno.d.ts",
          contents:
            "declare const Deno: { serve(handler: (request: Request) => Response | Promise<Response>): unknown };\n",
        },
        {
          path: "tsconfig.json",
          contents: JSON.stringify({
            extends: join(packageRoot, "tsconfig.json"),
            compilerOptions: {
              noEmit: true,
              module: "esnext",
              moduleResolution: "bundler",
              declaration: false,
              isolatedDeclarations: false,
              // Templates read NEXT_PUBLIC_* as `process.env.NAME` so Next
              // can inline them; consumers' ProcessEnv has no such keys.
              noPropertyAccessFromIndexSignature: false,
              rootDir: packageRoot,
              paths: {
                "better-supabase": [join(src, "index.ts")],
                "better-supabase/*": [join(src, "*", "index.ts")],
              },
            },
            include: ["**/*.ts", "**/*.tsx"],
          }),
        },
      ]) {
        await mkdir(dirname(join(root, file.path)), { recursive: true });
        await writeFile(join(root, file.path), file.contents);
      }
      const tsc = join(packageRoot, "node_modules/.bin/tsc");
      const result = await promisify(execFile)(
        tsc,
        ["--noEmit", "-p", join(root, "tsconfig.json")],
        {
          cwd: root,
        },
      ).then(
        () => ({ code: 0, output: "" }),
        (error: { code?: number; stdout?: string }) => ({
          code: error.code ?? 1,
          output: error.stdout ?? "",
        }),
      );
      expect(result.output).toBe("");
      expect(result.code).toBe(0);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  }, 120_000);
});

describe("env", () => {
  const status = {
    API_URL: "http://127.0.0.1:54321",
    DB_URL: "postgresql://postgres:postgres@127.0.0.1:54322/postgres",
    PUBLISHABLE_KEY: "sb_publishable_test",
    SECRET_KEY: "sb_secret_test",
    JWT_SECRET: "jwt-secret-test",
  };

  it("merges the stack into .env.local without printing values", async () => {
    await project(
      { next: "16" },
      {
        "status.json": JSON.stringify(status),
        ".env.local": "OTHER=1\nNEXT_PUBLIC_SUPABASE_URL=old\n",
        ".gitignore": ".env*.local\n",
      },
    );
    const result = await run(["env", "--from", "status.json", "--cwd", dir]);
    expect(result.code).toBe(0);
    expect(result.stdout).toContain("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY");
    expect(result.stdout).not.toContain("sb_secret_test");
    expect(result.stdout).not.toContain("Warning");
    const written = await readFile(join(dir, ".env.local"), "utf8");
    expect(written).toMatch(
      /^OTHER=1\nNEXT_PUBLIC_SUPABASE_URL=http:\/\/127\.0\.0\.1:54321\n/,
    );
    expect(written).toContain("SUPABASE_SECRET_KEY=sb_secret_test");
    expect(written).toContain("SUPABASE_JWT_SECRET=jwt-secret-test");
    expect(
      (await run(["env", "--from", "status.json", "--cwd", dir])).stdout,
    ).toContain("Unchanged");
  });

  it("runs supabase status through $SUPABASE_BIN", async () => {
    await project({});
    const bin = join(dir, "fake-supabase");
    await writeFile(
      bin,
      `#!/bin/sh\necho 'Starting...'\necho '${JSON.stringify({ ...status, PUBLISHABLE_KEY: undefined, ANON_KEY: "eyJlegacy" })}'\n`,
    );
    await chmod(bin, 0o755);
    const result = await run(
      ["env", "--print", "--prefix", "VITE_", "--cwd", dir],
      {
        io: { stdout: () => {}, stderr: () => {}, env: { SUPABASE_BIN: bin } },
      },
    );
    expect(result.code).toBe(0);
    expect(result.stdout).toContain("VITE_SUPABASE_PUBLISHABLE_KEY=eyJlegacy");
  });

  it("keeps comments and export lines when merging", () => {
    expect(mergeEnv("# mine\nexport A=1\n", { A: "2", B: "3" })).toBe(
      "# mine\nA=2\n\n# Local Supabase stack (better-supabase env)\nB=3\n",
    );
  });
});

describe("keys", () => {
  it("writes a private ES256 key that signs, and rotates", async () => {
    await project({}, { "supabase/config.toml": "[auth]\n" });
    const first = await run(["keys", "--cwd", dir]);
    expect(first.code).toBe(0);
    expect(first.stdout).toContain('signing_keys_path = "./signing_keys.json"');
    const path = join(dir, "supabase/signing_keys.json");
    expect((await stat(path)).mode & 0o777).toBe(0o600);
    const [key] = JSON.parse(await readFile(path, "utf8")) as JsonWebKey[];
    expect(first.stdout).not.toContain(key!.d!);
    const imported = await crypto.subtle.importKey(
      "jwk",
      key!,
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["sign"],
    );
    const signature = await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      imported,
      new Uint8Array([1]),
    );
    expect(signature.byteLength).toBe(64);

    expect((await run(["keys", "--cwd", dir])).code).toBe(1);
    const rotated = await run(["keys", "--rotate", "--cwd", dir]);
    expect(rotated.stdout).toContain("1 older key kept");
    const keys = JSON.parse(await readFile(path, "utf8")) as { kid: string }[];
    expect(keys).toHaveLength(2);
    expect(keys[1]!.kid).toBe((key as { kid: string }).kid);
  });
});

describe("read sets", () => {
  const readSetModule = `import { defineSupabase } from ${JSON.stringify(join(src, "core/define.ts"))};
import { defineReadSet } from ${JSON.stringify(join(src, "core/read-set.ts"))};
import { schema } from ${JSON.stringify(join(packageRoot, "tests/fixtures/generated-camel.ts"))};

const sb = defineSupabase(schema);

export const chrome = defineReadSet(sb, 'chrome', { params: { orgId: 'uuid' } }, (s, p) => ({
  customers: s.customers.count({ where: { organizationId: p.orgId, status: 'active' } }),
}));
`;

  it("compiles config.readSets into the read-sets module and checks drift", async () => {
    await project(
      {},
      {
        "better-supabase.config.ts": `export default { readSets: ['src/read-sets.ts'], sql: { kit: ['read-sets'] } };\n`,
        "src/read-sets.ts": readSetModule,
      },
    );
    const added = await run(["sql", "add", "read-sets", "--cwd", dir]);
    expect(added.stderr).toBe("");
    const path = join(
      dir,
      "supabase/schemas/900_better_supabase_14_read_sets.sql",
    );
    const sql = await readFile(path, "utf8");
    expect(sql).toContain(
      "create or replace function public.rs_chrome(p jsonb)",
    );
    expect(sql).toContain("((p->>'orgId')::uuid)");
    expect((await run(["sql", "sync", "--check", "--cwd", dir])).code).toBe(0);

    await writeFile(path, sql.replace("'active'", "'lead'"));
    const stale = await run(["sql", "sync", "--check", "--cwd", dir]);
    expect(stale.code).toBe(1);
    expect(stale.stderr).toContain("read_sets");
  });
});

describe("seed", () => {
  it("renders the seed module, refuses foreign files and checks drift", async () => {
    await project(
      {},
      {
        "supabase/config.toml": '[db.seed]\nsql_paths = ["./seed.sql"]\n',
        "supabase/seed.ts": `import { defineSupabase } from ${JSON.stringify(join(src, "core/define.ts"))};
import { schema } from ${JSON.stringify(join(packageRoot, "tests/fixtures/generated-camel.ts"))};
import { defineSeed } from ${JSON.stringify(join(src, "testing/seed.ts"))};

export const seed = defineSeed(defineSupabase(schema), {
  customers: { acme: { id: 'c1', organizationId: 'o1', name: "Acme's" } },
  organizations: { one: { id: 'o1', name: 'One', slug: 'one' } },
});
`,
      },
    );
    const result = await run(["seed", "--cwd", dir]);
    expect(result.stderr).toBe("");
    expect(result.stdout).toContain(
      "Wrote supabase/seeds/000_better_supabase.sql (2 tables)",
    );
    expect(result.stdout).toContain(
      'sql_paths = ["./seed.sql", "./seeds/000_better_supabase.sql"]',
    );
    const sql = await readFile(
      join(dir, "supabase/seeds/000_better_supabase.sql"),
      "utf8",
    );
    expect(sql.indexOf('"organizations"')).toBeLessThan(
      sql.indexOf('"customers"'),
    );
    expect(sql).toContain("'Acme''s'");
    expect((await run(["seed", "--check", "--cwd", dir])).code).toBe(0);
    await writeFile(
      join(dir, "supabase/seeds/000_better_supabase.sql"),
      "-- hand written\n",
    );
    expect((await run(["seed", "--check", "--cwd", dir])).code).toBe(1);
    const refused = await run(["seed", "--cwd", dir]);
    expect(refused.code).toBe(1);
    expect(refused.stderr).toContain("not written by better-supabase");
  });
});

describe("openapi emit", () => {
  it("writes the exported document and detects drift", async () => {
    await project(
      {},
      {
        "openapi.mjs":
          "export const openapi = () => ({ openapi: '3.1.0', info: { title: 'x', version: '1' }, paths: {} });\n",
        "bad.mjs": "export default { nope: true };\n",
      },
    );
    const emit = await run([
      "openapi",
      "emit",
      "--entry",
      "openapi.mjs",
      "--cwd",
      dir,
    ]);
    expect(emit.stdout).toContain("Wrote openapi.json");
    expect(
      JSON.parse(await readFile(join(dir, "openapi.json"), "utf8")),
    ).toMatchObject({ openapi: "3.1.0" });
    expect(
      (
        await run([
          "openapi",
          "emit",
          "--check",
          "--entry",
          "openapi.mjs",
          "--cwd",
          dir,
        ])
      ).code,
    ).toBe(0);
    await writeFile(join(dir, "openapi.json"), "{}\n");
    expect(
      (
        await run([
          "openapi",
          "emit",
          "--check",
          "--entry",
          "openapi.mjs",
          "--cwd",
          dir,
        ])
      ).code,
    ).toBe(1);
    expect(
      (await run(["openapi", "emit", "--entry", "bad.mjs", "--cwd", dir])).code,
    ).toBe(1);
    expect((await run(["openapi", "--cwd", dir])).code).toBe(2);
  });
});

describe("skills", () => {
  it("ships skills with names that match their folders", async () => {
    const skills = await loadSkills();
    expect(skills.map((skill) => skill.name)).toEqual([
      "better-supabase",
      "better-supabase-api",
      "better-supabase-testing",
    ]);
    for (const skill of skills) {
      expect(skill.contents).toMatch(
        new RegExp(
          `^---\\nname: ${skill.name}\\ndescription: .{20,1024}\\n---\\n`,
        ),
      );
    }
  });

  it("installs into detected agent folders and checks them", async () => {
    await project({}, { ".cursor/rules/.keep": "", ".claude/.keep": "" });
    const install = await run(["skills", "install", "--cwd", dir]);
    expect(install.stdout).toContain(
      "Wrote .cursor/skills/better-supabase/SKILL.md",
    );
    expect(install.stdout).toContain(
      "Wrote .claude/skills/better-supabase-testing/SKILL.md",
    );
    expect(install.stdout).toContain(
      "Wrote .cursor/skills/better-supabase/references/troubleshooting.md",
    );
    expect(install.stdout).not.toContain(".agents");
    expect(
      (await run(["skills", "install", "--check", "--cwd", dir])).code,
    ).toBe(0);
    await writeFile(
      join(dir, ".cursor/skills/better-supabase/SKILL.md"),
      "old",
    );
    expect(
      (await run(["skills", "install", "--check", "--cwd", dir])).code,
    ).toBe(1);
    const agents = await run([
      "skills",
      "install",
      "--agent",
      "agents",
      "--cwd",
      dir,
    ]);
    expect(agents.stdout).toContain(
      ".agents/skills/better-supabase-api/SKILL.md",
    );
    expect(
      (await run(["skills", "install", "--agent", "vim", "--cwd", dir])).code,
    ).toBe(2);
  });
});
