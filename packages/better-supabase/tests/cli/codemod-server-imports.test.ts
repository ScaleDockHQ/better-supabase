import { describe, expect, it } from "vitest";

import { moveServerImports } from "../../src/cli/codemod-server-imports.ts";

describe("codemod server-imports", () => {
  it("splits an import into the subpaths the names moved to", () => {
    const result = moveServerImports(
      'import { createServer, deleteAccount, toCsv, type RateLimitState } from "better-supabase/server";\n',
    );

    expect(result.text).toBe(
      [
        'import { createServer } from "better-supabase/server";',
        'import { deleteAccount } from "better-supabase/server/accounts";',
        'import { toCsv } from "better-supabase/server/csv";',
        'import { type RateLimitState } from "better-supabase/server/rate-limit";',
        "",
      ].join("\n"),
    );

    expect(result.review).toHaveLength(1);
  });

  it("keeps a type-only import type-only and honours aliases", () => {
    const result = moveServerImports(
      'import type { SuspendAccountResult as R, ServerOptions } from "better-supabase/server";',
    );

    expect(result.text).toContain(
      'import type { SuspendAccountResult as R } from "better-supabase/server/accounts";',
    );
    expect(result.text).toContain(
      'import type { ServerOptions } from "better-supabase/server";',
    );
  });

  it("splits a re-export the same way", () => {
    const result = moveServerImports(
      'export { createServer, toCsv } from "better-supabase/server";\nexport type { RateLimitState } from "better-supabase/server";\n',
    );

    expect(result.text).toBe(
      [
        'export { createServer } from "better-supabase/server";',
        'export { toCsv } from "better-supabase/server/csv";',
        'export type { RateLimitState } from "better-supabase/server/rate-limit";',
        "",
      ].join("\n"),
    );
  });

  it("leaves an import that moved nothing alone", () => {
    const text = 'import { createServer } from "better-supabase/server";\n';

    expect(moveServerImports(text)).toEqual({ text, review: [] });
  });
});
