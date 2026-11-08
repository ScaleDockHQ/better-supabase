import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { run } from "../../../src/cli/core/run.ts";

describe("init and the hooks framework", () => {
  let dir = "";

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "bsb-init-hooks-"));
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  const init = async (dependencies: Record<string, string>) => {
    await writeFile(
      join(dir, "package.json"),
      JSON.stringify({ name: "app", dependencies }),
    );

    expect(
      (await run(["init", "--preset", "minimal", "--cwd", dir])).code,
    ).toBe(0);

    return readFile(join(dir, "better-supabase.config.ts"), "utf-8");
  };

  it("writes gen.hooks for a framework no adapter selects", async () => {
    expect(await init({ vue: "3" })).toContain(
      "output: 'lib/supabase/generated.ts', hooks: 'vue' }",
    );
  });

  it("leaves it out when an adapter already selects the framework", async () => {
    expect(await init({ next: "16", react: "19" })).not.toContain("hooks:");
  });

  it("writes the templates and names the server adapter of a registered framework", async () => {
    await writeFile(
      join(dir, "package.json"),
      JSON.stringify({ name: "app", dependencies: { "@acme/qwik": "1" } }),
    );

    await writeFile(
      join(dir, "better-supabase.config.ts"),
      `const qwik = {
  apiVersion: 1,
  name: 'qwik',
  tier: 'community',
  detect: ['@acme/qwik'],
  serverSubpath: 'qwik-server',
  templates: (context) => [
    { path: context.srcDir + '/qwik.ts', contents: "import '" + context.serverImport + "';\\n" },
  ],
};

export default { gen: { frameworks: [qwik] } };
`,
    );

    const result = await run(["init", "--preset", "minimal", "--cwd", dir]);

    expect(result.code).toBe(0);
    expect(result.stdout).toContain(
      "Server adapter for qwik: better-supabase/qwik-server.",
    );
    expect(await readFile(join(dir, "qwik.ts"), "utf-8")).toBe(
      "import 'better-supabase/qwik-server';\n",
    );
  });
});
