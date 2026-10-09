import { describe, expect, expectTypeOf, it, vi } from "vitest";

import type { AiFiles } from "../../src/blocks/ai-files/index.ts";
import type { AiTaskOutcome } from "../../src/blocks/ai-tasks/index.ts";
import type { BlockContext } from "../../src/blocks/index.ts";
import type { CloudEvent } from "../../src/events/index.ts";

import { createAuditLog } from "../../src/blocks/audit/index.ts";
import {
  BLOCK_EVENT_SOURCE,
  createBlocks,
  rpcTransport,
} from "../../src/blocks/index.ts";
import { createOrganizations } from "../../src/blocks/organizations/index.ts";
import { emitBlockEvent } from "../../src/core/block-events.ts";
import { EventHub } from "../../src/core/events.ts";
import { vaultCredentials } from "../../src/credentials/index.ts";

const transport = rpcTransport({
  schema: () => ({
    rpc: () => Promise.resolve({ data: null, error: null }),
  }),
});

const fakeFiles = {} as AiFiles;

describe("createBlocks", () => {
  it("builds each block with the shared options and types the result", () => {
    const blocks = createBlocks(
      { transport, schema: "api" },
      { organizations: createOrganizations, audit: createAuditLog },
    );
    expect(typeof blocks.organizations.create).toBe("function");
    expect(typeof blocks.audit.sink).toBe("function");
    expectTypeOf(blocks.organizations).toEqualTypeOf<
      ReturnType<typeof createOrganizations>
    >();
    blocks.close();
  });

  it("wires aiFiles, credentials and events into the siblings", () => {
    const credentials = vaultCredentials({ transport });
    const events = new EventHub();
    const seen: BlockContext[] = [];
    const aiFiles = vi.fn(() => fakeFiles);
    createBlocks(
      { transport, credentials, events },
      {
        knowledge: (context) => seen.push(context),
        aiFiles,
        connectors: (context) => seen.push(context),
      },
    );
    expect(aiFiles).toHaveBeenCalledTimes(1);
    expect(aiFiles.mock.calls[0]).not.toHaveProperty("0.files");
    for (const context of seen)
      expect(context).toMatchObject({
        transport,
        credentials,
        events,
        files: fakeFiles,
      });
  });

  it("sends the ai-task notification through the notifications block", async () => {
    const send = vi.fn(() => Promise.resolve("n1"));
    let notify: BlockContext["notify"];
    createBlocks(
      { transport, aiTaskNotification: "ai_task.finished" },
      {
        aiTasks: (context) => (notify = context.notify),
        notifications: () => ({ send }),
      },
    );
    const outcome = {
      task: { id: "t1", userId: "u1", organizationId: "o1" },
      run: { id: "r1" },
      ok: false,
      error: "boom",
    } as AiTaskOutcome;
    await notify?.(outcome);
    expect(send).toHaveBeenCalledWith("ai_task.finished", {
      recipients: ["u1"],
      tenant: "o1",
      key: "ai-task-run:r1",
      data: { taskId: "t1", runId: "r1", ok: false, error: "boom" },
    });
  });

  it("leaves notify out without a notification type", () => {
    const seen: BlockContext[] = [];
    createBlocks(
      { transport },
      {
        aiTasks: (context) => seen.push(context),
        notifications: () => ({ send: vi.fn() }),
      },
    );
    expect(seen[0]).not.toHaveProperty("notify");
  });

  it("rejects a notifications block that cannot send", () => {
    let notify: BlockContext["notify"];
    createBlocks(
      { transport, aiTaskNotification: "done" },
      {
        aiTasks: (context) => (notify = context.notify),
        notifications: () => 1,
      },
    );
    expect(() => notify?.({} as AiTaskOutcome)).toThrow(/no send method/);
  });

  it("forwards block events to audit until close", async () => {
    const events = new EventHub();
    const sent: CloudEvent[] = [];
    const blocks = createBlocks(
      {
        transport,
        events,
        audit: { send: (batch) => void sent.push(...batch) },
      },
      {},
    );
    const denied = { adminId: "a1", targetUserId: "u1" };
    emitBlockEvent(events, "support.denied", denied);
    await events.settled();
    expect(sent).toHaveLength(1);
    expect(sent[0]).toMatchObject({
      source: BLOCK_EVENT_SOURCE,
      type: "dev.better-supabase.support.denied",
    });
    blocks.close();
    emitBlockEvent(events, "support.denied", denied);
    await events.settled();
    expect(sent).toHaveLength(1);
  });

  it("needs events to forward to audit", () => {
    expect(() =>
      createBlocks({ transport, audit: { send: () => undefined } }, {}),
    ).toThrow(/needs `events`/);
  });

  it("reports a block that depends on itself", () => {
    const outcome = {
      task: { id: "t1", userId: "u1", organizationId: "o1" },
      run: { id: "r1" },
      ok: true,
    } as AiTaskOutcome;
    expect(() =>
      createBlocks(
        { transport, aiTaskNotification: "done" },
        {
          notifications: (context) => {
            context.notify?.(outcome);
            return { send: vi.fn() };
          },
        },
      ),
    ).toThrow(/depends on itself/);
  });
});
