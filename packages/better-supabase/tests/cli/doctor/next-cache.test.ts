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

  it("names next.config when none was read", () => {
    const findings = check({
      sources: [
        { path: "src/a.ts", text: 'const mode = "use cache: remote";' },
      ],
    });

    expect(findings[0]?.message).toContain("next.config sets no remote");
    expect(findings[0]?.location?.line).toBe(1);
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

describe("BS610", () => {
  const rule = NEXT_CACHE_RULES.find((candidate) => candidate.code === "BS610");

  const run = (text: string) => {
    // SAFETY: BS610 reads only `sources`.
    const findings = rule?.check({
      sources: [{ path: "src/data.ts", text }],
    } as unknown as DoctorContext);

    if (!Array.isArray(findings)) {
      throw new TypeError("BS610 runs synchronously");
    }

    return findings;
  };

  it("flags a private scope that calls another one", () => {
    const findings = run(
      [
        "export async function inner() {",
        '  "use cache: private";',
        "  return 1;",
        "}",
        "",
        "export const outer = async () => {",
        '  "use cache: private";',
        "  return await inner();",
        "};",
      ].join("\n"),
    );

    expect(findings).toHaveLength(1);
    expect(findings[0]?.message).toContain("outer");
    expect(findings[0]?.message).toContain("inner");
    expect(findings[0]?.location?.line).toBe(6);
  });

  it("stays quiet when the scopes don't call each other", () => {
    expect(
      run(
        [
          "async function a() {",
          '  "use cache: private";',
          "  return 1;",
          "}",
          "async function b() {",
          '  "use cache: private";',
          "  return 2;",
          "}",
        ].join("\n"),
      ),
    ).toEqual([]);
  });

  it("ignores a method with the name of another private scope", () => {
    expect(
      run(
        [
          "export async function getSession() {",
          '  "use cache: private";',
          "  return 1;",
          "}",
          "export async function loadSession(id: string) {",
          '  "use cache: private";',
          "  return await db.tills.getSession(id);",
          "}",
        ].join("\n"),
      ),
    ).toEqual([]);
  });
});

describe("BS611", () => {
  const rule = NEXT_CACHE_RULES.find((candidate) => candidate.code === "BS611");

  const run = (text: string) => {
    // SAFETY: BS611 reads only `sources`.
    const findings = rule?.check({
      sources: [{ path: "src/data.ts", text }],
    } as unknown as DoctorContext);

    if (!Array.isArray(findings)) {
      throw new TypeError("BS611 runs synchronously");
    }

    return findings;
  };

  it("flags an admin client in a private scope", () => {
    const findings = run(
      'async function load() { "use cache: private"; const db = bsb.admin(); return db; }',
    );

    expect(findings).toHaveLength(1);
  });

  it("allows an admin read outside the scope", () => {
    expect(
      run(
        'async function load() { "use cache: private"; return 1; }\nasync function other() { return bsb.admin(); }',
      ),
    ).toHaveLength(0);
  });
});
