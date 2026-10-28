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

  it("lists the removed cache lifetime helpers and the token overload", () => {
    const source = `import { sessionStale } from "better-supabase/next";

cacheLife({ stale: sessionStale(session) });
await bsb.cached({ life: { max: 900 } });
await bsb.contextFromSession(session, { token });
await bsb.cached({ life: { stale: 900 } });
`;

    const review = applyCodemod(v035, source, "src/data.ts").review;

    expect(review.map((line) => line.line)).toEqual([1, 3, 4, 5]);
    expect(review.map((line) => line.message)).toEqual([
      expect.stringContaining("`sessionStale` is gone"),
      expect.stringContaining("`sessionStale` is gone"),
      expect.stringContaining("`life.min` and `life.max` are gone"),
      expect.stringContaining("SessionSnapshot"),
    ]);
  });

  it("renames the SessionProvider sessionPromise prop and flags sessionStatusRoute", () => {
    const source = `<SessionProvider sessionPromise={bsb.claims()}>{children}</SessionProvider>;
export const GET = sessionStatusRoute(bsb);
`;

    const result = applyCodemod(v035, source, "app/layout.tsx");

    expect(result.text)
      .toBe(`<SessionProvider session={bsb.claims()}>{children}</SessionProvider>;
export const GET = sessionStatusRoute(bsb);
`);
    expect(result.review.map((line) => line.line)).toEqual([2]);
  });

  it("renames supabaseFor calls to contextClient and flags the rest", () => {
    const source = `const client = server.supabaseFor(ctx.auth);
const label = "server.supabaseFor(auth)";
const { supabaseFor } = server;
export const server = createServer({ sessions: false });
`;

    const result = applyCodemod(v035, source, "src/server.ts");

    expect(result.text).toBe(`const client = server.contextClient(ctx.auth);
const label = "server.supabaseFor(auth)";
const { supabaseFor } = server;
export const server = createServer({ sessions: false });
`);
    expect(result.review.map((line) => line.message)).toEqual([
      expect.stringContaining("now `contextClient`"),
      expect.stringContaining("verifies its token again"),
    ]);
  });

  it("passes a literal transition reason as { reason } and flags the rest", () => {
    const source = `await machine.transition(subject, "won", "Signed");
await machine.transition({ type: "deal", id }, "lost", \`Lost to \${rival}\`);
await machine.transition(subject, "won");
await machine.transition(subject, "won", { reason: "Signed" });
await machine.transition(subject, "won", reason);
const label = 'machine.transition(subject, "won", "Signed")';
`;

    const result = applyCodemod(v035, source, "src/deals.ts");

    expect(result.text)
      .toBe(`await machine.transition(subject, "won", { reason: "Signed" });
await machine.transition({ type: "deal", id }, "lost", { reason: \`Lost to \${rival}\` });
await machine.transition(subject, "won");
await machine.transition(subject, "won", { reason: "Signed" });
await machine.transition(subject, "won", reason);
const label = 'machine.transition(subject, "won", "Signed")';
`);
    expect(result.review.map((line) => line.line)).toEqual([5]);
    expect(result.review[0]?.message).toContain("pass `{ reason }`");
  });

  it("passes the step library to validateGraph as { steps }, and flags forget and kind maps", () => {
    const source = `const a = validateGraph(graph, steps);
const b = validateGraph(draft, library.steps);
const c = validateGraph(graph);
const d = validateGraph(graph, { steps });
await memory.archival.forget(id);
const icons = {} satisfies Record<WorkflowNodeKind, Icon>;
`;

    const result = applyCodemod(v035, source, "src/graph.ts");

    expect(result.text).toBe(`const a = validateGraph(graph, { steps });
const b = validateGraph(draft, { steps: library.steps });
const c = validateGraph(graph);
const d = validateGraph(graph, { steps });
await memory.archival.forget(id);
const icons = {} satisfies Record<WorkflowNodeKind, Icon>;
`);
    expect(result.review.map((line) => line.message)).toEqual([
      expect.stringContaining("soft deletes now"),
      expect.stringContaining("WorkflowBuiltinNodeKind"),
    ]);
  });
});
