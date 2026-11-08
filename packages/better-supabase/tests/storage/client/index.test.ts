import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";

import { defineBucket } from "../../../src/storage/client/index.ts";
import { defineBucket as defineServerBucket } from "../../../src/storage/index.ts";

const config = {
  id: "customer-logos",
  path: "{organizationId}/{customerId}/logo/{version}.webp",
  policy: "tenant",
  tenant: { param: "organizationId" },
  fileSizeLimit: "5MiB",
  allowedMimeTypes: ["image/webp"],
  variants: { square: { width: 56, height: 56, resize: "cover" } },
} as const;

const values = { organizationId: "org", customerId: "c1", version: "1" };

describe("storage client defineBucket", () => {
  const client = defineBucket(config);
  const server = defineServerBucket(config);

  it("builds the same paths, matches and limits as the server bucket", () => {
    expect(client.path(values)).toEqual(server.path(values));
    expect(client.match("org/c1/logo/1.webp")).toEqual(values);
    expect(client.prefix({ organizationId: "org" })).toBe(
      server.prefix({ organizationId: "org" }),
    );
    expect(client.check({ size: 6 * 1024 * 1024 })).toEqual(
      server.check({ size: 6 * 1024 * 1024 }),
    );
    expect(client.check({ type: "image/png" })?.status).toBe(415);
  });

  it("carries no SQL, config, drift or admin methods", () => {
    expect(Object.keys(client).toSorted()).not.toContain("sql");

    for (const name of ["sql", "toml", "drift", "apply"]) {
      expect(name in client).toBe(false);
    }
  });

  it("validates the tenant parameter like the server bucket", () => {
    expect(() =>
      defineBucket({ ...config, tenant: { param: "missing" } }),
    ).toThrow(/missing/);
  });

  it("connects and builds public URLs", () => {
    const storage = client.connect({
      storage: {
        from: () => ({
          getPublicUrl: (path: string) => ({
            data: { publicUrl: `https://x.test/${path}` },
          }),
        }),
      },
    } as never);

    expect(
      storage.publicUrl("org/c1/logo/1.webp", { transform: "square" }),
    ).toBeDefined();
  });

  it("imports none of the SQL, policy or template-string modules", async () => {
    const seen = new Set<string>();
    const queue = ["storage/client/index.ts"];

    while (queue.length > 0) {
      const file = queue.pop()!;

      if (seen.has(file)) {
        continue;
      }

      seen.add(file);

      const source = await readFile(
        new URL(`../../../src/${file}`, import.meta.url),
        "utf-8",
      );

      for (const [, specifier] of source.matchAll(
        /^(?:import|export)\s(?!type\s)[^;]*?from\s+"(\.[^"]+)"/gm,
      )) {
        const base = file.split("/").slice(0, -1);

        for (const part of specifier!.split("/")) {
          if (part === "..") {
            base.pop();
          } else if (part !== ".") {
            base.push(part);
          }
        }

        queue.push(base.join("/"));
      }
    }

    for (const forbidden of [
      "storage/bucket.ts",
      "storage/policy.ts",
      "storage/apply.ts",
      "core/access-sql.ts",
    ]) {
      expect(seen).not.toContain(forbidden);
    }
  });
});
