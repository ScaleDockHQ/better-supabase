import { mkdtemp, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";

import { run } from "../../../src/cli/core/run.ts";

const roots: string[] = [];

afterAll(async () => {
  await Promise.all(
    roots.map((root) => rm(root, { recursive: true, force: true })),
  );
});

async function project(): Promise<string> {
  const root = await mkdtemp(join(tmpdir(), "bsb-cache-equal-"));
  roots.push(root);
  await writeFile(join(root, "package.json"), "{}");

  await writeFile(
    join(root, "better-supabase.config.json"),
    JSON.stringify({
      blocks: {
        organizations: {},
        memberships: {},
        tags: {},
        comments: {},
        audit: {},
      },
    }),
  );

  return root;
}

/** Every file under `supabase`, by path. */
async function files(root: string): Promise<Record<string, string>> {
  const names = await readdir(join(root, "supabase"), { recursive: true });

  const entries = await Promise.all(
    names
      .filter((name) => name.endsWith(".sql"))
      .toSorted()
      .map(
        async (name) =>
          [
            name,
            await readFile(join(root, "supabase", name), "utf-8"),
          ] as const,
      ),
  );

  return Object.fromEntries(entries);
}

describe("upgrade with and without the cache", () => {
  it("writes the same files cold, warm and under --no-cache", async () => {
    const cached = await project();
    const fresh = await project();

    expect((await run(["upgrade", "--cwd", cached])).code).toBe(0);

    // The first run's files change the layout the second one sees, so the
    // third is the no-op that the cache answers.
    await run(["upgrade", "--cwd", cached]);
    const warm = await run(["upgrade", "--cwd", cached, "--json"]);
    expect(warm.code).toBe(0);
    expect(JSON.parse(warm.stdout)).toMatchObject({
      data: { cache: { rendered: 0 } },
    });

    for (let pass = 0; pass < 3; pass += 1) {
      expect((await run(["upgrade", "--cwd", fresh, "--no-cache"])).code).toBe(
        0,
      );
    }

    expect(Object.keys(await files(cached)).length).toBeGreaterThan(3);
    expect(await files(fresh)).toStrictEqual(await files(cached));
  });
});
