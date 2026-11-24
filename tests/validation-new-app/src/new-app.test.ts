import { run } from "better-supabase/cli";
import { rm } from "node:fs/promises";
import { afterEach, describe, expect, it } from "vitest";

import type { NewApp } from "./fixture.ts";

import { newApp, readFiles, startStack, typecheck } from "./fixture.ts";

const dirs: string[] = [];

afterEach(async () => {
  await Promise.all(
    dirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })),
  );
});

const fresh = async (app: NewApp): Promise<string> => {
  const dir = await newApp(app);

  dirs.push(dir);

  return dir;
};

// Every adapter tier-1 app and one app per package manager. SvelteKit, TanStack
// Start and React Router have bindings of their own (ADR 0582): `init` writes
// `gen.hooks`, their server middleware file and a hint for the server adapter.
const APPS: readonly (NewApp & {
  readonly install: string;
  readonly adapters: readonly string[];
  readonly framework?: { readonly file: string; readonly server: string };
})[] = [
  {
    name: "next",
    dependencies: { next: "16.0.0", react: "19.0.0" },
    manager: "pnpm",
    install: "pnpm add",
    adapters: ["client", "next"],
  },
  {
    name: "hono",
    dependencies: { hono: "4.0.0" },
    manager: "npm",
    install: "npm install",
    adapters: ["hono"],
  },
  {
    name: "expo",
    dependencies: { expo: "55.0.0", react: "19.0.0" },
    manager: "yarn",
    install: "yarn add",
    adapters: ["client", "expo"],
  },
  {
    name: "vite",
    dependencies: { vite: "7.0.0", react: "19.0.0" },
    manager: "bun",
    install: "bun add",
    adapters: ["client"],
  },
  {
    name: "sveltekit",
    dependencies: { "@sveltejs/kit": "2.0.0", svelte: "5.0.0", vite: "7.0.0" },
    manager: "pnpm",
    install: "pnpm add",
    adapters: ["client"],
    framework: { file: "src/hooks.server.ts", server: "sveltekit" },
  },
  {
    name: "tanstack-start",
    dependencies: {
      "@tanstack/react-start": "1.0.0",
      react: "19.0.0",
      vite: "7.0.0",
    },
    manager: "npm",
    install: "npm install",
    adapters: ["client"],
    framework: { file: "lib/supabase/middleware.ts", server: "tanstack-start" },
  },
  {
    name: "react-router",
    dependencies: {
      "@react-router/dev": "7.0.0",
      "react-router": "7.0.0",
      react: "19.0.0",
      vite: "7.0.0",
    },
    manager: "yarn",
    install: "yarn add",
    adapters: ["client"],
    framework: {
      file: "lib/supabase/middleware.server.ts",
      server: "react-router",
    },
  },
];

// The first command loads the CLI from source, which takes about 5 s on a CI
// runner, and each case runs tsc.
const TIMEOUT = 120_000;

describe.each(APPS)("init --yes in a new $name app", (app) => {
  it(
    "detects the project, writes a short config and changes none of the app's files",
    { timeout: TIMEOUT },
    async () => {
      const dir = await fresh(app);
      const before = await readFiles(dir);
      const init = await run(["init", "--yes", "--cwd", dir]);

      expect(init).toMatchObject({ code: 0 });
      expect(`${init.stdout}${init.stderr}`).toContain(
        `${app.install} better-supabase`,
      );

      const after = await readFiles(dir);

      for (const [path, text] of before) {
        expect(after.get(path)).toBe(text);
      }

      const config = after.get("better-supabase.config.ts") ?? "";

      expect(config.split("\n").length).toBeLessThan(16);

      for (const adapter of app.adapters) {
        expect(config).toContain(`'${adapter}'`);
      }

      // Nothing the app has to fill in: values init doesn't write are inferred.
      expect(config).not.toMatch(/tenant|organization/i);
      expect(
        [...after.keys()].some((path) => path.startsWith("supabase")),
      ).toBe(false);
    },
  );

  it(
    "runs gen against the new stack, then typechecks with no edit",
    { timeout: TIMEOUT },
    async () => {
      const dir = await fresh(app);

      expect(await run(["init", "--yes", "--cwd", dir])).toMatchObject({
        code: 0,
      });

      await startStack(dir);

      const gen = await run([
        "gen",
        "--snapshot",
        "supabase/snapshot.json",
        "--cwd",
        dir,
      ]);

      expect(gen).toMatchObject({ code: 0 });

      expect(
        await run([
          "gen",
          "--check",
          "--snapshot",
          "supabase/snapshot.json",
          "--cwd",
          dir,
        ]),
      ).toMatchObject({ code: 0 });

      await typecheck(dir, ["lib/supabase/index.ts"]);
    },
  );
});

const FRAMEWORK_APPS = APPS.flatMap(({ framework, ...app }) =>
  framework === undefined ? [] : [{ ...app, ...framework }],
);

describe.each(FRAMEWORK_APPS)("init --yes in a new $name app", (app) => {
  it(
    "writes the server file of its binding and names the server adapter",
    { timeout: TIMEOUT },
    async () => {
      const dir = await fresh(app);
      const init = await run(["init", "--yes", "--cwd", dir]);
      const after = await readFiles(dir);

      expect(init).toMatchObject({ code: 0 });
      expect(after.get(app.file)).toContain(`better-supabase/${app.server}`);
      expect(init.stderr + init.stdout).toContain(
        `Server adapter for ${app.name}: better-supabase/${app.server}.`,
      );
      expect(after.get("better-supabase.config.ts")).toContain(
        `hooks: '${app.name}'`,
      );
    },
  );
});
