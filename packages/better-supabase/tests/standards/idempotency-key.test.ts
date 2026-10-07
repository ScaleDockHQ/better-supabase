import { describe, expect, it } from "vitest";

import { createIdempotency } from "../../src/blocks/jobs/index.ts";
import { fakeSql } from "../fixtures/fake-sql.ts";

/** An in-memory `better_supabase.begin_idempotent` with the SQL module's semantics. */
function store() {
  const rows = new Map<
    string,
    { fingerprint: string; status: number | null; response: unknown }
  >();
  return fakeSql([
    [
      "begin_idempotent",
      ({ values: [scope, key, fingerprint] }) => {
        const id = `${String(scope)}:${String(key)}`;
        const row = rows.get(id);
        if (!row) {
          rows.set(id, {
            fingerprint: String(fingerprint),
            status: null,
            response: null,
          });
          return [{ state: "started", status_code: null, response: null }];
        }
        if (row.fingerprint !== fingerprint)
          return [{ state: "mismatch", status_code: null, response: null }];
        if (row.status === null)
          return [{ state: "running", status_code: null, response: null }];
        return [
          { state: "replay", status_code: row.status, response: row.response },
        ];
      },
    ],
    [
      "complete_idempotent",
      ({ values: [scope, key, status, body] }) => {
        rows.get(`${String(scope)}:${String(key)}`)!.status = Number(status);
        rows.get(`${String(scope)}:${String(key)}`)!.response = JSON.parse(
          String(body),
        );
        return [];
      },
    ],
    [
      "release_idempotent",
      ({ values: [scope, key] }) => {
        rows.delete(`${String(scope)}:${String(key)}`);
        return [];
      },
    ],
  ]);
}

const post = (
  key: string | undefined,
  body = '{"amount":10}',
  path = "/payments",
) =>
  new Request(`https://api.test${path}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(key === undefined ? {} : { "Idempotency-Key": key }),
    },
    body,
  });

describe("Idempotency-Key header (IETF draft-ietf-httpapi-idempotency-key-header)", () => {
  it("runs the handler once per key and replays the stored response", async () => {
    const idempotency = createIdempotency(store().sql);
    let calls = 0;
    const handler = () => {
      calls += 1;
      return Response.json({ id: `pay_${calls}` }, { status: 201 });
    };
    const first = await idempotency.handle(post("k1"), handler);
    const second = await idempotency.handle(post("k1"), handler);
    expect(calls).toBe(1);
    expect(first.status).toBe(201);
    expect(second.status).toBe(201);
    expect(await second.json()).toEqual({ id: "pay_1" });
    expect(second.headers.get("content-type")).toMatch(/^application\/json/);
    expect(second.headers.get("idempotency-replayed")).toBe("true");
  });

  it("answers 422 when a key is reused with a different payload (section 2.7)", async () => {
    const idempotency = createIdempotency(store().sql);
    await idempotency.handle(post("k2"), () => new Response("ok"));
    const reused = await idempotency.handle(
      post("k2", '{"amount":99}'),
      () => new Response("again"),
    );
    expect(reused.status).toBe(422);
    expect(reused.headers.get("content-type")).toBe("application/problem+json");
    expect(await reused.json()).toMatchObject({
      code: "IDEMPOTENCY_KEY_REUSED",
    });
  });

  it("answers 409 with Retry-After while the first request is still running (section 2.7)", async () => {
    const idempotency = createIdempotency(store().sql);
    let release!: () => void;
    let started!: () => void;
    const running = new Promise<void>((resolve) => {
      started = resolve;
    });
    const slow = idempotency.handle(
      post("k3"),
      () =>
        new Promise<Response>((resolve) => {
          release = () => {
            resolve(new Response("done"));
          };
          started();
        }),
    );
    await running;
    const concurrent = await idempotency.handle(
      post("k3"),
      () => new Response("second"),
    );
    expect(concurrent.status).toBe(409);
    expect(concurrent.headers.get("retry-after")).toBe("1");
    release();
    expect((await slow).status).toBe(200);
  });

  it("answers in the app's error format with the problem option", async () => {
    const idempotency = createIdempotency(store().sql, {
      required: true,
      problem: (problem, error) => ({
        type: `https://errors.example.com/${error.code ?? "unknown"}`,
        title: problem.title,
        status: problem.status,
        errorCode: error.code,
      }),
    });
    const missing = await idempotency.handle(
      post(undefined),
      () => new Response("ok"),
    );
    expect(missing.status).toBe(400);
    expect(missing.headers.get("content-type")).toBe(
      "application/problem+json",
    );
    expect(await missing.json()).toEqual({
      type: "https://errors.example.com/IDEMPOTENCY_KEY_MISSING",
      title: "Invalid request",
      status: 400,
      errorCode: "IDEMPOTENCY_KEY_MISSING",
    });
  });

  it("answers 400 when the header is required and missing (section 2.7)", async () => {
    const idempotency = createIdempotency(store().sql, { required: true });
    const missing = await idempotency.handle(
      post(undefined),
      () => new Response("ok"),
    );
    expect(missing.status).toBe(400);
    expect(await missing.json()).toMatchObject({
      code: "IDEMPOTENCY_KEY_MISSING",
    });
    const optional = createIdempotency(store().sql);
    expect(
      await (
        await optional.handle(post(undefined), () => new Response("ran"))
      ).text(),
    ).toBe("ran");
  });

  it("rejects keys longer than 255 characters", async () => {
    const response = await createIdempotency(store().sql).handle(
      post("k".repeat(256)),
      () => new Response("ok"),
    );
    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({
      code: "IDEMPOTENCY_KEY_INVALID",
    });
  });

  it("releases the key when the handler fails, so a retry can run (server errors are not stored)", async () => {
    const idempotency = createIdempotency(store().sql);
    expect(
      (
        await idempotency.handle(
          post("k4"),
          () => new Response("boom", { status: 503 }),
        )
      ).status,
    ).toBe(503);
    expect(
      await (
        await idempotency.handle(post("k4"), () => new Response("retried"))
      ).text(),
    ).toBe("retried");
    await expect(
      idempotency.handle(post("k5"), () => {
        throw new Error("crash");
      }),
    ).rejects.toThrow("crash");
    expect(
      await (
        await idempotency.handle(post("k5"), () => new Response("after crash"))
      ).text(),
    ).toBe("after crash");
  });

  it("scopes keys, so the same key on another endpoint or tenant is independent", async () => {
    const idempotency = createIdempotency(store().sql, {
      scope: (request) => new URL(request.url).pathname,
    });
    await idempotency.handle(post("k6", "{}", "/a"), () => new Response("a"));
    expect(
      await (
        await idempotency.handle(
          post("k6", "{}", "/b"),
          () => new Response("b"),
        )
      ).text(),
    ).toBe("b");
  });

  it("uses a custom header name and passes TTL and lock as intervals", async () => {
    const sql = store();
    const idempotency = createIdempotency(sql.sql, {
      header: "x-request-id",
      ttl: 60,
      lock: "5 seconds",
    });
    const request = new Request("https://api.test/x", {
      method: "POST",
      headers: { "x-request-id": "r1" },
      body: "{}",
    });
    await idempotency.handle(request, () => new Response("ok"));
    expect(sql.calls[0]!.values.slice(3)).toEqual(["60 seconds", "5 seconds"]);
  });
});
