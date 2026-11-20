import { describe, expect, it } from "vitest";

import { chatIdOf, persistSessions } from "../../src/eve/sessions.ts";
import { sessionChatId } from "../../src/eve/sync.ts";
import { memoryStore } from "./memory-store.ts";

const ctx = { session: { id: "sess_1", auth: { current: null } } };

describe("persistSessions", () => {
  it("only wakes the session's sync job", async () => {
    const store = memoryStore();
    const hooks = persistSessions({ store });
    await hooks["turn.started"]({ type: "turn.started", data: {} }, ctx);
    await hooks["content.completed"](
      { type: "content.completed", data: {} },
      ctx,
    );
    expect(store.wakes).toEqual(["sess_1", "sess_1"]);
  });

  it("passes the delay on", async () => {
    const delays: (number | undefined)[] = [];

    const hooks = persistSessions({
      store: {
        wake: (_id, delay) => {
          delays.push(delay);

          return Promise.resolve();
        },
      },
      delaySeconds: 7,
    });

    await hooks["session.ended"]({ type: "session.ended", data: {} }, ctx);
    expect(delays).toEqual([7]);
  });

  it("keeps the chat id of a session", async () => {
    expect(await chatIdOf("sess_1")).toBe(await sessionChatId("sess_1"));
  });
});
