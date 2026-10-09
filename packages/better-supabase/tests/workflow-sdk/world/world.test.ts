import type { Pool } from "pg";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const inner = vi.fn(
  async (_request: Request): Promise<Response> =>
    new Response("{}", { status: 200 }),
);
const baseClose = vi.fn(async () => undefined);
const reenqueue = vi.fn(async () => undefined);

vi.mock("@workflow/world-postgres", () => ({
  createWorld: () => ({
    runs: {},
    createQueueHandler: () => inner,
    close: baseClose,
  }),
}));
vi.mock("@workflow/world", () => ({
  reenqueueActiveRuns: reenqueue,
}));

const {
  createSupabaseWorld,
  createWorld,
  deriveRunKey,
  parseMasterKey,
  resolveFlowUrl,
  signDelivery,
  verifyDelivery,
  WORKFLOW_WORLD_PROTOCOL,
  worldOptionsFromEnv,
} = await import("../../../src/workflow-sdk/world/index.ts");

interface Query {
  readonly fn: string;
  readonly params: readonly unknown[];
}

/** A pool whose functions answer from `replies`, keyed by function name. */
function fakePool(replies: Record<string, (params: unknown[]) => unknown[]>): {
  pool: Pool;
  queries: Query[];
} {
  const queries: Query[] = [];
  const query = vi.fn(async (text: string, params: unknown[] = []) => {
    const fn = text.includes("vault.decrypted_secrets")
      ? "vault"
      : (/"?([a-z_]+)"?\(/.exec(text.replace(/^select \* from /, ""))?.[1] ??
        "");
    queries.push({ fn, params });
    const reply = replies[fn];
    return { rows: reply === undefined ? [] : reply(params) };
  });
  const end = vi.fn(async () => undefined);
  // SAFETY: the World only calls query and end on its pool.
  return { pool: { query, end } as unknown as Pool, queries };
}

function stored(attempt = 1, extra: Record<string, unknown> = {}) {
  return {
    queueName: "__wkf_workflow_test",
    messageId: "msg_1",
    attempt,
    body: Buffer.from(JSON.stringify({ runId: "wrun_1" })).toString("base64"),
    headers: { "x-custom": "1" },
    ...extra,
  };
}

const ENV_KEYS = [
  "WORKFLOW_FLOW_URL",
  "WORKFLOW_LOCAL_BASE_URL",
  "PORT",
] as const;
const saved: Record<string, string | undefined> = {};

beforeEach(() => {
  for (const key of ENV_KEYS) {
    saved[key] = process.env[key];
    delete process.env[key];
  }
  inner.mockClear();
  reenqueue.mockClear();
});

afterEach(() => {
  vi.unstubAllEnvs();
  for (const key of ENV_KEYS) {
    if (saved[key] === undefined) delete process.env[key];
    else process.env[key] = saved[key];
  }
  vi.unstubAllGlobals();
});

describe("delivery signatures", () => {
  it("verifies its own signature within five minutes", async () => {
    const now = 1_760_000_000_000;
    const header = await signDelivery("s", "q:1:1", "{}", now);
    expect(header).toMatch(/^t=1760000000,v1=[0-9a-f]{64}$/);
    expect(await verifyDelivery("s", header, "q:1:1", "{}", now)).toBe(true);
    expect(
      await verifyDelivery("s", header, "q:1:1", "{}", now + 299_000),
    ).toBe(true);
    expect(
      await verifyDelivery("s", header, "q:1:1", "{}", now + 301_000),
    ).toBe(false);
    expect(await verifyDelivery("x", header, "q:1:1", "{}", now)).toBe(false);
    expect(await verifyDelivery("s", header, "q:1:2", "{}", now)).toBe(false);
    expect(await verifyDelivery("s", null, "", "{}", now)).toBe(false);
    expect(await verifyDelivery("s", "t=abc,v1=00", "", "{}", now)).toBe(false);
    expect(await verifyDelivery("s", "v1=00", "", "{}", now)).toBe(false);
  });

  it("matches the database's hmac over t.job.body", async () => {
    // hmac-sha256('1.j.b', 'k'), as extensions.hmac computes it.
    const header = await signDelivery("k", "j", "b", 1000);
    expect(header).toBe(
      `t=1,v1=${Buffer.from(
        await crypto.subtle.sign(
          "HMAC",
          await crypto.subtle.importKey(
            "raw",
            new TextEncoder().encode("k"),
            { name: "HMAC", hash: "SHA-256" },
            false,
            ["sign"],
          ),
          new TextEncoder().encode("1.j.b"),
        ),
      ).toString("hex")}`,
    );
  });
});

describe("encryption keys", () => {
  it("parses base64 and hex master keys of at least 32 bytes", () => {
    const hex = "ab".repeat(32);
    expect(parseMasterKey(hex)).toHaveLength(32);
    expect(parseMasterKey(Buffer.alloc(32, 1).toString("base64"))).toHaveLength(
      32,
    );
    expect(() => parseMasterKey("short")).toThrow("at least 32 bytes");
  });

  it("derives a different key per run", async () => {
    const master = new Uint8Array(32).fill(7);
    const a = await deriveRunKey(master, "wrun_a");
    const b = await deriveRunKey(master, "wrun_b");
    expect(a).toHaveLength(32);
    expect(Buffer.from(a).equals(Buffer.from(b))).toBe(false);
    expect(
      Buffer.from(await deriveRunKey(master, "wrun_a")).equals(Buffer.from(a)),
    ).toBe(true);
  });
});

describe("options", () => {
  it("resolves the flow route from options, then the environment", () => {
    expect(resolveFlowUrl("https://app.test/flow")).toBe(
      "https://app.test/flow",
    );
    expect(resolveFlowUrl()).toBe(
      "http://localhost:3000/.well-known/workflow/v1/flow",
    );
    vi.stubEnv("PORT", "4100");
    expect(resolveFlowUrl()).toBe(
      "http://localhost:4100/.well-known/workflow/v1/flow",
    );
    vi.stubEnv("WORKFLOW_LOCAL_BASE_URL", "https://app.test/base/?x=1#h");
    expect(resolveFlowUrl()).toBe(
      "https://app.test/base/.well-known/workflow/v1/flow",
    );
    vi.stubEnv("WORKFLOW_FLOW_URL", "https://env.test/flow");
    expect(resolveFlowUrl()).toBe("https://env.test/flow");
  });

  it("reads the World options from the environment", () => {
    expect(
      worldOptionsFromEnv({
        DATABASE_URL: "postgres://d",
        SUPABASE_DB_URL: "postgres://s",
        WORKFLOW_DELIVERY: "pg_net",
        WORKFLOW_FLOW_URL: "https://f",
        WORKFLOW_DELIVERY_SECRET: "sec",
        WORKFLOW_ENCRYPTION_KEY: "key",
        WORKFLOW_DELIVERY_QUEUE: "q",
        WORKFLOW_QUEUE_NAMESPACE: "ns",
        WORKFLOW_POSTGRES_WORKER_CONCURRENCY: "5",
        WORKFLOW_POSTGRES_POLL_INTERVAL_MS: "x",
      }),
    ).toEqual({
      connectionString: "postgres://s",
      delivery: "pg_net",
      flowUrl: "https://f",
      deliverySecret: "sec",
      encryptionKey: "key",
      queue: "q",
      namespace: "ns",
      concurrency: 5,
    });
    expect(worldOptionsFromEnv({ WORKFLOW_POSTGRES_URL: "" })).toEqual({});
    expect(() => worldOptionsFromEnv({ WORKFLOW_DELIVERY: "push" })).toThrow(
      'WORKFLOW_DELIVERY must be "poll" or "pg_net"',
    );
  });

  it("names the protocol it speaks and builds from the environment", async () => {
    expect(WORKFLOW_WORLD_PROTOCOL).toMatch(/^\d+\.\d+\.\d+$/);
    const world = createWorld();
    expect(typeof world.queue).toBe("function");
    await world.close();
  });
});

describe("createSupabaseWorld", () => {
  it("stores messages in the jobs queue and polls them to the flow route", async () => {
    const jobs: unknown[] = [];
    const { pool, queries } = fakePool({
      enqueue_job: (params) => {
        jobs.push(JSON.parse(String(params[1])));
        return [{ enqueue_job: 1 }];
      },
      claim_jobs: () =>
        jobs.splice(0).map((payload, index) => ({
          id: index + 1,
          attempts: 1,
          message: { payload },
        })),
      complete_job: () => [{ complete_job: true }],
      vault: () => [],
    });
    const fetch = vi.fn(
      async (_url: string, _init: RequestInit) =>
        new Response(JSON.stringify({ timeoutSeconds: 5 }), { status: 200 }),
    );
    vi.stubGlobal("fetch", fetch);
    const world = createSupabaseWorld({
      pool,
      flowUrl: "https://app.test/flow",
      deliverySecret: "sec",
      pollInterval: 10,
    });
    await world.close();

    const { messageId } = await world.queue(
      "__wkf_workflow_test",
      { runId: "wrun_1", bytes: new Uint8Array([0, 1]) } as never,
      { idempotencyKey: "k1", delaySeconds: 1.2, headers: { "x-h": "v" } },
    );
    expect(messageId).toMatch(/^msg_/);
    const enqueue = queries.find((query) => query.fn === "enqueue_job");
    expect(enqueue?.params.slice(2)).toEqual([2, 73, "k1", false]);

    expect(await world.deliverOnce()).toBe(1);
    const [url, init] = fetch.mock.calls[0]!;
    expect(url).toBe("https://app.test/flow");
    const headers = new Headers(init.headers);
    expect(headers.get("x-vqs-queue-name")).toBe("__wkf_workflow_test");
    expect(headers.get("x-vqs-message-attempt")).toBe("1");
    expect(headers.get("x-h")).toBe("v");
    expect(headers.get("x-bs-signature")).toMatch(/^t=\d+,v1=/);
    // timeoutSeconds re-queues the message as its next attempt.
    expect(jobs).toHaveLength(1);
    expect(jobs[0]).toMatchObject({ attempt: 2 });
    expect(queries.map((query) => query.fn)).toContain("complete_job");
  });

  it("polls in the background once a message is queued, and survives a failed claim", async () => {
    const jobs: unknown[] = [];
    let claims = 0;
    const { pool, queries } = fakePool({
      enqueue_job: (params) => {
        jobs.push(JSON.parse(String(params[1])));
        return [{ enqueue_job: 1 }];
      },
      claim_jobs: () => {
        claims += 1;
        if (claims === 1) throw new Error("claim failed");
        return jobs.splice(0).map((payload, index) => ({
          id: index + 1,
          attempts: 1,
          message: { payload },
        }));
      },
      complete_job: () => [{ complete_job: true }],
      vault: () => [],
    });
    const fetch = vi.fn(async () => new Response("{}", { status: 200 }));
    vi.stubGlobal("fetch", fetch);
    const world = createSupabaseWorld({
      pool,
      flowUrl: "https://app.test/flow",
      deliverySecret: "sec",
      pollInterval: 5,
    });

    await world.queue("__wkf_workflow_test", { runId: "wrun_1" });
    await vi.waitFor(() => {
      expect(queries.map((query) => query.fn)).toContain("complete_job");
    });
    expect(fetch).toHaveBeenCalledOnce();
    expect(claims).toBeGreaterThan(1);
    await world.close();
  });

  it("fails a job the route refuses, or that is not a workflow message", async () => {
    const { pool, queries } = fakePool({
      claim_jobs: () => [
        { id: 1, attempts: 2, message: { payload: stored(1) } },
        { id: 2, attempts: 1, message: { payload: { nope: true } } },
      ],
      fail_job: () => [{ fail_job: "retry" }],
      vault: () => [],
    });
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response("boom", { status: 500 })),
    );
    const world = createSupabaseWorld({ pool, flowUrl: "https://app.test/f" });
    expect(await world.deliverOnce()).toBe(2);
    const fails = queries.filter((query) => query.fn === "fail_job");
    expect(fails.map((query) => query.params[3])).toEqual(
      expect.arrayContaining([
        "Flow route answered 500: boom",
        "Not a workflow message",
      ]),
    );
    await world.close();
  });

  it("fails a job when the route can't be reached", async () => {
    const { pool, queries } = fakePool({
      claim_jobs: () => [
        { id: 1, attempts: 1, message: { payload: stored() } },
      ],
      fail_job: () => [],
      vault: () => [],
    });
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        throw new Error("refused");
      }),
    );
    const world = createSupabaseWorld({ pool, flowUrl: "https://app.test/f" });
    await world.deliverOnce();
    expect(queries.find((query) => query.fn === "fail_job")?.params[3]).toBe(
      "refused",
    );
    await world.close();
  });

  it("reports the messages of a batch it could not store", async () => {
    let calls = 0;
    const { pool } = fakePool({
      enqueue_job: () => {
        calls += 1;
        if (calls === 2) throw new Error("full");
        return [];
      },
    });
    const world = createSupabaseWorld({ pool, delivery: "pg_net" });
    const results = await world.queueBatch!("__wkf_step_x", [
      { message: { a: 1 } as never },
      { message: { a: 2 } as never },
    ]);
    expect(results[0]?.messageId).toMatch(/^msg_/);
    expect(results[1]).toEqual({
      messageId: null,
      error: "full",
      retryable: true,
    });
    await world.close();
  });

  it("verifies signed deliveries from pg_net and settles their job", async () => {
    const { pool, queries } = fakePool({
      vault: (params) =>
        params[0] === "workflow_delivery_secret" ? [{ secret: "sec" }] : [],
      complete_job: () => [],
      fail_job: () => [],
      extend_job_lease: () => [],
    });
    const world = createSupabaseWorld({ pool, delivery: "pg_net" });
    const handler = world.createQueueHandler("__wkf_workflow_", async () => {});
    const body = JSON.stringify(stored(1));
    const job = "workflow_deliveries:7:1";
    const signed = await signDelivery("sec", job, body);
    const request = (headers: Record<string, string>, text = body) =>
      new Request("https://app.test/flow", {
        method: "POST",
        headers,
        body: text,
      });

    const ok = await handler(
      request({ "x-bs-job": job, "x-bs-signature": signed }),
    );
    expect(ok.status).toBe(200);
    const forwarded = inner.mock.calls[0]![0];
    expect(forwarded.headers.get("x-vqs-message-id")).toBe("msg_1");
    expect(forwarded.headers.get("x-bs-job")).toBeNull();
    expect(await forwarded.text()).toBe(JSON.stringify({ runId: "wrun_1" }));
    expect(
      queries.find((query) => query.fn === "complete_job")?.params,
    ).toEqual(["workflow_deliveries", "7", 1]);

    expect(
      (
        await handler(
          request({ "x-bs-job": job, "x-bs-signature": "t=1,v1=0" }),
        )
      ).status,
    ).toBe(401);
    const badJob = "other:x:1";
    expect(
      (
        await handler(
          request({
            "x-bs-job": badJob,
            "x-bs-signature": await signDelivery("sec", badJob, body),
          }),
        )
      ).status,
    ).toBe(400);
    expect((await handler(request({}))).status).toBe(401);
    const plain = await handler(
      request({ "x-bs-signature": await signDelivery("sec", "", "{}") }, "{}"),
    );
    expect(plain.status).toBe(200);

    inner.mockRejectedValueOnce(new Error("crash"));
    await expect(
      handler(
        request({
          "x-bs-job": job,
          "x-bs-signature": await signDelivery("sec", job, body),
        }),
      ),
    ).rejects.toThrow("crash");
    expect(queries.filter((query) => query.fn === "fail_job")).toHaveLength(1);
    await world.close();
  });

  it("passes unsigned requests through in poll mode without a secret only in development and test", async () => {
    const unsigned = () =>
      new Request("https://app.test/flow", { method: "POST", body: "{}" });
    for (const mode of ["development", "test"]) {
      vi.stubEnv("NODE_ENV", mode);
      const { pool } = fakePool({ vault: () => [] });
      const world = createSupabaseWorld({ pool });
      const handler = world.createQueueHandler("__wkf_step_", async () => {});
      expect((await handler(unsigned())).status).toBe(200);
      await world.close();
    }
    for (const mode of ["production", ""]) {
      vi.stubEnv("NODE_ENV", mode);
      inner.mockClear();
      const { pool } = fakePool({ vault: () => [] });
      const world = createSupabaseWorld({ pool });
      const handler = world.createQueueHandler("__wkf_step_", async () => {});
      const response = await handler(unsigned());
      expect(response.status).toBe(401);
      expect(response.headers.get("content-type")).toBe(
        "application/problem+json",
      );
      expect(await response.json()).toMatchObject({
        code: "WORKFLOW_DELIVERY_REJECTED",
        detail: expect.stringContaining("WORKFLOW_DELIVERY_SECRET"),
      });
      expect(inner).not.toHaveBeenCalled();
      await world.close();
    }
  });

  it("derives run keys from the Vault key and re-enqueues active runs on start", async () => {
    const master = Buffer.alloc(32, 3).toString("base64");
    const { pool } = fakePool({
      vault: (params) =>
        params[0] === "workflow_encryption_key" ? [{ secret: master }] : [],
      claim_jobs: () => [],
    });
    const world = createSupabaseWorld({ pool, pollInterval: 10 });
    const key = await world.getEncryptionKeyForRun!("wrun_1");
    expect(key).toEqual(await deriveRunKey(parseMasterKey(master), "wrun_1"));
    expect(
      await world.getEncryptionKeyForRun!({ runId: "wrun_1" } as never),
    ).toEqual(key);
    await world.start();
    expect(reenqueue).toHaveBeenCalledOnce();
    await world.close();
    expect(baseClose).toHaveBeenCalled();

    const { pool: plain } = fakePool({ vault: () => [] });
    const open = createSupabaseWorld({ pool: plain });
    expect(await open.getEncryptionKeyForRun!("wrun_1")).toBeUndefined();
    await open.close();
  });

  it("fails closed on an unreadable Vault and reads it again next time", async () => {
    let broken = true;
    const master = Buffer.alloc(32, 3).toString("base64");
    const { pool, queries } = fakePool({
      vault: (params) => {
        if (broken) throw new Error("permission denied for schema vault");
        return params[0] === "workflow_encryption_key"
          ? [{ secret: master }]
          : [{ secret: "sec" }];
      },
    });
    const world = createSupabaseWorld({ pool });
    await expect(world.getEncryptionKeyForRun!("wrun_1")).rejects.toThrow(
      "permission denied",
    );
    const handler = world.createQueueHandler("__wkf_step_", async () => {});
    const unsigned = () =>
      new Request("https://app.test/flow", { method: "POST", body: "{}" });
    const response = await handler(unsigned());
    expect(response.status).toBe(503);
    expect(inner).not.toHaveBeenCalled();

    broken = false;
    expect(await world.getEncryptionKeyForRun!("wrun_1")).toEqual(
      await deriveRunKey(parseMasterKey(master), "wrun_1"),
    );
    expect((await handler(unsigned())).status).toBe(401);
    const reads = queries.filter((query) => query.fn === "vault").length;
    await world.getEncryptionKeyForRun!("wrun_2");
    await handler(unsigned());
    expect(queries.filter((query) => query.fn === "vault")).toHaveLength(reads);
    await world.close();
  });

  it("fails a poll delivery whose secret can't be read, without posting it", async () => {
    const { pool, queries } = fakePool({
      claim_jobs: () => [
        { id: 1, attempts: 1, message: { payload: stored() } },
      ],
      fail_job: () => [],
      vault: () => {
        throw new Error("vault down");
      },
    });
    const fetch = vi.fn(async () => new Response("{}", { status: 200 }));
    vi.stubGlobal("fetch", fetch);
    const world = createSupabaseWorld({ pool, flowUrl: "https://app.test/f" });
    await world.deliverOnce();
    expect(fetch).not.toHaveBeenCalled();
    expect(queries.find((query) => query.fn === "fail_job")?.params[3]).toBe(
      "vault down",
    );
    await world.close();
  });

  it("aborts a delivery the flow route doesn't answer within the timeout", async () => {
    vi.useFakeTimers();
    try {
      const { pool, queries } = fakePool({
        claim_jobs: () => [
          { id: 1, attempts: 1, message: { payload: stored() } },
        ],
        fail_job: () => [],
        extend_job_lease: () => [],
        vault: () => [],
      });
      let seen: AbortSignal | undefined;
      vi.stubGlobal(
        "fetch",
        vi.fn(
          (_url: string, init: RequestInit) =>
            new Promise<Response>((_resolve, reject) => {
              seen = init.signal ?? undefined;
              init.signal?.addEventListener("abort", () => {
                reject(new Error("timed out"));
              });
            }),
        ),
      );
      const world = createSupabaseWorld({
        pool,
        flowUrl: "https://app.test/f",
        lease: 10,
        deliveryTimeout: 20,
      });
      const delivered = world.deliverOnce();
      await vi.advanceTimersByTimeAsync(19_000);
      expect(seen?.aborted).toBe(false);
      const extended = queries.filter(
        (query) => query.fn === "extend_job_lease",
      ).length;
      expect(extended).toBeGreaterThan(0);
      await vi.advanceTimersByTimeAsync(1_000);
      await delivered;
      expect(seen?.aborted).toBe(true);
      expect(queries.find((query) => query.fn === "fail_job")?.params[3]).toBe(
        "timed out",
      );
      await vi.advanceTimersByTimeAsync(60_000);
      expect(
        queries.filter((query) => query.fn === "extend_job_lease"),
      ).toHaveLength(extended);
      await world.close();
    } finally {
      vi.useRealTimers();
    }
  });
});
