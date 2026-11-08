import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { describe, expect, it } from "vitest";

import type { TemplateContext } from "../../src/cli/templates.ts";

import { TEMPLATES } from "../../src/cli/templates.ts";

const FIXTURE = resolve(
  import.meta.dirname,
  "../../../../tests/init-fixture/nextjs",
);

const context: TemplateContext = {
  srcDir: "src",
  generated: "src/lib/supabase/generated.ts",
  tsExtensions: false,
  frameworks: ["next"],
  version: "1.2.3",
};

const files = TEMPLATES.next.files(context);

describe("the Next.js init fixture", () => {
  it("is what init writes for Next.js (INIT_FIXTURE_UPDATE=1 rewrites it)", async () => {
    for (const file of files) {
      const path = resolve(FIXTURE, file.path);

      if (process.env["INIT_FIXTURE_UPDATE"]) {
        await mkdir(dirname(path), { recursive: true });
        await writeFile(path, file.contents);
      }

      expect({ path: file.path, text: await readFile(path, "utf-8") }).toEqual({
        path: file.path,
        text: file.contents,
      });
    }
  });

  it("writes the feature-sliced layout, the PWA files and the Web Push keys", () => {
    const paths = files.map((file) => file.path);

    expect(paths).toEqual(
      expect.arrayContaining([
        "src/app/(app)/layout.tsx",
        "src/app/(app)/account/[section]/page.tsx",
        "src/features/auth/auth-queries.ts",
        "src/features/auth/auth-actions.ts",
        "src/features/account/account-cache.ts",
        "src/features/account/components/account-section.tsx",
        "src/app/manifest.ts",
        "public/sw.js",
        "public/offline.html",
        ".env.example",
      ]),
    );

    const env = files.find((file) => file.path === ".env.example");

    expect(env?.contents).toContain("NEXT_PUBLIC_VAPID_PUBLIC_KEY=\n");
    expect(env?.contents).toContain("VAPID_PRIVATE_KEY=\n");
    expect(env?.contents).not.toMatch(/KEY=\S/);
  });

  it("keeps the worker away from private responses and POSTs", () => {
    const worker = files.find((file) => file.path === "public/sw.js");

    expect(worker?.contents).toContain("private|no-store");
    expect(worker?.contents).toContain("request.method !== 'GET'");
  });

  it("stays out of the proxy for html and the manifest", () => {
    const proxy = files.find((file) => file.path === "src/proxy.ts");

    expect(proxy?.contents).toContain("html|webmanifest");
  });
});
