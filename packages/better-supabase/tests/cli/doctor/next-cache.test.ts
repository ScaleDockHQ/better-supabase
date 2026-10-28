import { describe, expect, it } from "vitest";

import type { DoctorContext, TextFile } from "../../../src/cli/doctor/rules.ts";

import { NEXT_CACHE_RULES } from "../../../src/cli/doctor/next-cache.ts";

const REMOTE: TextFile = {
  path: "src/app/inbox/data.ts",
  text: [
    'import { bsb } from "@/lib/supabase/server";',
    "",
    "export const inbox = bsb.remote(async (key) => {",
    '  "use cache: remote";',
    "});",
  ].join("\n"),
};

function check(
  context: Pick<DoctorContext, "sources" | "nextConfig" | "vercel">,
): readonly { message: string; location?: { line: number } }[] {
  const [rule] = NEXT_CACHE_RULES;
  // SAFETY: BS608 reads only `sources`, `nextConfig` and `vercel`.
  const findings = rule?.check(context as unknown as DoctorContext);

  if (!Array.isArray(findings)) {
    throw new TypeError("BS608 runs synchronously");
  }

  return findings;
}

describe("BS608", () => {
  it("warns on a remote scope outside Vercel without a remote handler", () => {
    const findings = check({
      sources: [REMOTE],
      nextConfig: {
        path: "next.config.ts",
        text: "export default createNextConfig();",
      },
    });

    expect(findings).toHaveLength(1);
    expect(findings[0]?.message).toContain(
      "next.config.ts sets no remote cache handler",
    );
    expect(findings[0]?.location?.line).toBe(3);
  });

  it("stays quiet with a remote handler or on Vercel", () => {
    for (const text of [
      'createNextConfig({ remoteCacheHandler: "./cache/remote.mjs" })',
      'export default { cacheHandlers: { remote: require.resolve("./r") } }',
    ]) {
      expect(
        check({
          sources: [REMOTE],
          nextConfig: { path: "next.config.ts", text },
        }),
      ).toEqual([]);
    }

    expect(check({ sources: [REMOTE], vercel: true })).toEqual([]);
  });

  it("stays quiet without a remote scope", () => {
    expect(
      check({
        sources: [
          { path: "src/a.ts", text: 'await bsb.cached({ scope: "private" });' },
        ],
      }),
    ).toEqual([]);
  });
});
