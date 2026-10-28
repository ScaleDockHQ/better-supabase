import { describe, expect, it } from "vitest";

import { applyCodemod, CODEMODS } from "../../src/cli/codemod.ts";

const v035 = CODEMODS["0.35"]!;

describe("codemod 0.35", () => {
  it("rewrites the navigation policies, outside strings and comments", () => {
    const source = `import { createExpo } from "better-supabase/expo";

// refresh: "navigation" was the default
export const middleware = bsb.middleware({ refresh: "navigation" });
export const session = { verifySession: 'navigation' };
const label = 'refresh: "navigation"';
`;

    expect(applyCodemod(v035, source, "src/server.ts").text)
      .toBe(`import { createExpo } from "better-supabase/expo";

// refresh: "navigation" was the default
export const middleware = bsb.middleware({ refresh: true });
export const session = { verifySession: 'document' };
const label = 'refresh: "navigation"';
`);
  });

  it("lists the removed exports and the async clearSessionCookies for review", () => {
    const source = `import { clearSessionCookies, writeSession } from "better-supabase/server";

export const proxy = bsb.proxy(request, { onExpiredPrefetch: "render" });
clearSessionCookies(request, response);
`;

    const messages = applyCodemod(v035, source, "src/proxy.ts").review.map(
      (line) => line.message,
    );

    expect(messages).toEqual(
      expect.arrayContaining([
        expect.stringContaining("onExpiredPrefetch"),
        expect.stringContaining("await it"),
        expect.stringContaining("cookie codec"),
      ]),
    );
  });
});
