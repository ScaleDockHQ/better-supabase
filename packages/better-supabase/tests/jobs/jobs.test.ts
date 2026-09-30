import { describe, expect, it } from "vitest";
import { z } from "zod";

import { createJobs, type QueueRpcClient } from "../../src/jobs/index.ts";

interface Call {
  readonly schema: string;
  readonly fn: string;
  readonly args: Readonly<Record<string, unknown>>;
}

function fakeClient(respond: (call: Call) => unknown): {
  client: QueueRpcClient;
  calls: Call[];
} {
  const calls: Call[] = [];
  const client: QueueRpcClient = {
    schema: (schema) => ({
      rpc: (fn, args) => {
        const call = { schema, fn, args };
        calls.push(call);
        return Promise.resolve({ data: respond(call), error: null });
      },
    }),
  };
  return { client, calls };
}

describe("createJobs over pgmq_public", () => {
  it("sends, reads and archives through PostgREST", async () => {
    const { client, calls } = fakeClient(({ fn }) => {
      if (fn === "send") return [7];
      if (fn === "read") {
        return [
          {
            msg_id: 7,
            read_ct: 1,
            enqueued_at: "2026-09-24T10:00:00Z",
            vt: "2026-09-24T10:05:00Z",
            message: { payload: { to: "a@example.com" }, max_attempts: 1 },
          },
        ];
      }
      return true;
    });
    const jobs = createJobs(client, { emails: z.object({ to: z.email() }) });

    expect(
      await jobs
        .enqueue("emails", { to: "a@example.com" }, { delay: 5 })
        .orThrow(),
    ).toBe(7);
    const [job] = await jobs.claim("emails", { lease: 60 }).orThrow();
    expect(job).toMatchObject({
      id: 7,
      queue: "emails",
      attempts: 1,
      maxAttempts: 1,
      payload: { to: "a@example.com" },
      lastError: null,
    });
    expect(await jobs.fail(job!, "boom").orThrow()).toBe("dead");
    expect(calls).toEqual([
      {
        schema: "pgmq_public",
        fn: "send",
        args: {
          queue_name: "emails",
          message: { payload: { to: "a@example.com" }, max_attempts: 5 },
          sleep_seconds: 5,
        },
      },
      {
        schema: "pgmq_public",
        fn: "read",
        args: { queue_name: "emails", sleep_seconds: 60, n: 1 },
      },
      {
        schema: "pgmq_public",
        fn: "archive",
        args: { queue_name: "emails", message_id: 7 },
      },
    ]);
  });

  it("refuses SQL-only features and invalid queue names", async () => {
    const { client } = fakeClient(() => [1]);
    const jobs = createJobs(client, { emails: z.object({}) });
    const deduped = await jobs.enqueue("emails", {}, { dedupeKey: "x" });
    expect(deduped.error).toMatchObject({
      kind: "invalid_request",
      message: expect.stringContaining("dedupeKey needs a SQL connection"),
    });
    expect(
      (await jobs.schedule("nightly", "0 3 * * *", "emails", {})).error?.kind,
    ).toBe("invalid_request");
    expect(() => createJobs(client, { "send-emails": z.object({}) })).toThrow(
      "pgmq queue names",
    );
  });
});
