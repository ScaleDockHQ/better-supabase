import { describe, expect, it } from "vitest";

import type { IdempotencyClaims } from "../../src/core/idempotent-write.ts";

import { idempotentCall } from "../../src/core/idempotent-write.ts";
import { AsyncResult } from "../../src/core/result.ts";

type Begin =
  Awaited<ReturnType<IdempotencyClaims["begin"]>> extends infer R
    ? R extends { ok: true; data: infer D }
      ? D
      : never
    : never;

function claims(begin: Begin): IdempotencyClaims & { readonly log: string[] } {
  const log: string[] = [];

  return {
    log,
    begin: () => AsyncResult.ok(begin),
    complete: (input) => {
      log.push(`complete:${JSON.stringify(input.body)}`);

      return AsyncResult.ok(true);
    },
    release: () => {
      log.push("release");

      return AsyncResult.ok(true);
    },
  };
}

const started: Begin = {
  state: "started",
  status: null,
  body: null,
  holder: "token",
};

const call = (
  port: IdempotencyClaims | undefined,
  key: string | undefined,
  run: () => AsyncResult<unknown>,
) =>
  idempotentCall({
    claims: port,
    key,
    scope: "org",
    name: "create_thing",
    args: { a: 1n },
    run,
    decode: (raw) => ({ decoded: raw }),
  });

describe("idempotentCall", () => {
  it("runs a call without a key unclaimed", async () => {
    const result = await call(undefined, undefined, () => AsyncResult.ok(1));

    expect(result).toMatchObject({ ok: true, data: { decoded: 1 } });
  });

  it("needs the idempotency option for a key", async () => {
    const result = await call(undefined, "key", () => AsyncResult.ok(1));

    expect(!result.ok && result.error.hint).toBe("IDEMPOTENCY_NOT_CONFIGURED");
  });

  it("rejects an empty or long key", async () => {
    const port = claims(started);
    const empty = await call(port, "", () => AsyncResult.ok(1));
    const long = await call(port, "k".repeat(256), () => AsyncResult.ok(1));

    expect(!empty.ok && empty.error.hint).toBe("IDEMPOTENCY_KEY_INVALID");
    expect(!long.ok && long.error.hint).toBe("IDEMPOTENCY_KEY_INVALID");
  });

  it("stores the first response", async () => {
    const port = claims(started);
    const result = await call(port, "k", () => AsyncResult.ok({ id: "1" }));

    expect(result).toMatchObject({ ok: true, data: { decoded: { id: "1" } } });
    expect(port.log).toStrictEqual(['complete:{"id":"1"}']);
  });

  it("replays the stored response without running", async () => {
    const port = claims({
      state: "replay",
      status: 200,
      body: { id: "1" },
      holder: undefined,
    });

    let ran = false;

    const result = await call(port, "k", () => {
      ran = true;

      return AsyncResult.ok(2);
    });

    expect(ran).toBe(false);
    expect(result).toMatchObject({ ok: true, data: { decoded: { id: "1" } } });
  });

  it("releases the key when the call fails", async () => {
    const port = claims(started);

    const result = await call(port, "k", () =>
      AsyncResult.err({
        kind: "forbidden",
        message: "no",
        status: 403,
      } as never),
    );

    expect(result.ok).toBe(false);
    expect(port.log).toStrictEqual(["release"]);
  });

  it("answers conflict while the first call runs", async () => {
    const port = claims({
      state: "running",
      status: null,
      body: null,
      holder: undefined,
    });

    const result = await call(port, "k", () => AsyncResult.ok(1));

    expect(!result.ok && result.error.kind).toBe("conflict");
    expect(!result.ok && result.error.hint).toBe("IDEMPOTENCY_KEY_IN_USE");
  });

  it("answers validation for a key used with other arguments", async () => {
    const port = claims({
      state: "mismatch",
      status: null,
      body: null,
      holder: undefined,
    });

    const result = await call(port, "k", () => AsyncResult.ok(1));

    expect(!result.ok && result.error.kind).toBe("validation");
    expect(!result.ok && result.error.hint).toBe("IDEMPOTENCY_KEY_REUSED");
  });
});
