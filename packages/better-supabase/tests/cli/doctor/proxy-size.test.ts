import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";

import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";

import {
  PROXY_BUDGET_BYTES,
  PROXY_SIZE_RULES,
  readProxyTrace,
} from "../../../src/cli/doctor/proxy-size.ts";

const folders: string[] = [];

const project = async (sizes: Record<string, number>): Promise<string> => {
  const root = await mkdtemp(join(tmpdir(), "bsb-proxy-"));
  folders.push(root);
  await mkdir(join(root, ".next/server"), { recursive: true });

  for (const [name, size] of Object.entries(sizes)) {
    await writeFile(join(root, ".next/server", name), "x".repeat(size));
  }

  await writeFile(
    join(root, ".next/server/proxy.js.nft.json"),
    JSON.stringify({ version: 1, files: [...Object.keys(sizes), "gone.js"] }),
  );

  return root;
};

afterEach(async () => {
  await Promise.all(
    folders.splice(0).map((folder) => rm(folder, { recursive: true })),
  );
});

const run = (trace: Awaited<ReturnType<typeof readProxyTrace>>) => {
  // SAFETY: BS650 reads only `proxyTrace`.
  const findings = PROXY_SIZE_RULES[0]?.check({
    proxyTrace: trace,
  } as unknown as DoctorContext);

  if (!Array.isArray(findings)) {
    throw new TypeError("the rule runs synchronously");
  }

  return findings;
};

describe("BS650", () => {
  it("adds up the traced files and names the biggest", async () => {
    const trace = await readProxyTrace(
      await project({ "a.js": PROXY_BUDGET_BYTES, "b.js": 10 }),
    );

    expect(trace?.bytes).toBe(PROXY_BUDGET_BYTES + 10);
    expect(trace?.largest[0]?.file).toContain("a.js");
    expect(run(trace)).toHaveLength(1);
  });

  it("passes a proxy under the budget", async () => {
    expect(run(await readProxyTrace(await project({ "a.js": 1000 })))).toEqual(
      [],
    );
  });

  it("skips a project that was not built", async () => {
    const root = await mkdtemp(join(tmpdir(), "bsb-proxy-"));
    folders.push(root);

    expect(await readProxyTrace(root)).toBeUndefined();
    expect(run(undefined)).toEqual([]);
  });
});
