import { describe, expect, it } from "vitest";

import { createSessions } from "../../../src/blocks/sessions/index.ts";

function transport(
  answer: (fn: string, args: Record<string, unknown>) => unknown,
) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);

      return Promise.resolve(answer(fn, args));
    },
  };
}

const row = (id: string, current: boolean) => ({
  id,
  createdAt: "2026-10-01T00:00:00Z",
  lastActiveAt: "2026-10-02T00:00:00Z",
  userAgent: "Safari",
  ip: null,
  aal: "aal1",
  current,
});

describe("createSessions", () => {
  it("lists the caller's sessions", async () => {
    const sessions = createSessions({
      transport: transport(() => [row("a", true), row("b", false)]),
    });

    const list = await sessions.listMine().orThrow();

    expect(list.map((each) => [each.id, each.current])).toEqual([
      ["a", true],
      ["b", false],
    ]);
    expect(list[1]?.userAgent).toBe("Safari");
  });

  it("endOthers ends every session but the current one, through the hooks", async () => {
    const seen: string[] = [];

    const t = transport((fn) =>
      fn === "list_my_sessions"
        ? [row("a", true), row("b", false), row("c", false)]
        : true,
    );

    const sessions = createSessions({
      transport: t,
      hooks: { end: { before: ([input]) => void seen.push(input.sessionId) } },
    });

    expect(await sessions.endOthers().orThrow()).toEqual(["b", "c"]);
    expect(seen).toEqual(["b", "c"]);
    expect(t.calls.filter(([fn]) => fn === "end_my_session")).toEqual([
      ["end_my_session", { session: "b" }],
      ["end_my_session", { session: "c" }],
    ]);
  });
});
