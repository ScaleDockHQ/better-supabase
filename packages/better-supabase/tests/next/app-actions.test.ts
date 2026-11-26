import { beforeEach, describe, expect, expectTypeOf, it, vi } from "vitest";

import { createSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { createNext } from "../../src/next/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const mocks = vi.hoisted(() => ({ headers: new Headers() }));

vi.mock(import("next/headers.js"), () => ({
  headers: () => Promise.resolve(mocks.headers),
  cookies: () => Promise.resolve({ set: vi.fn(), getAll: () => [] } as never),
}));

vi.mock(import("next/cache.js"), () => ({
  updateTag: vi.fn(),
  revalidateTag: vi.fn(),
  refresh: vi.fn(),
  cacheTag: vi.fn(),
  cacheLife: () => undefined,
  io: () => Promise.resolve(),
}));

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const signer = await createTestSigner();
const refuseAll = vi.fn<() => undefined | ReturnType<typeof dbError>>();

const bsb = createNext(createSupabase(schema), {
  env: {
    url: PROJECT_URL,
    publishableKey: "sb_publishable_test",
    jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
  },
  auth: { jwks: signer.jwks },
  actions: {
    envelope: (outcome) => ({
      message: outcome.ok ? "Saved" : outcome.error.message,
    }),
    guard: () => refuseAll(),
    from: (value) =>
      typeof value === "object" && value !== null && "boxed" in value
        ? { ok: true, data: value.boxed }
        : undefined,
  },
});

beforeEach(async () => {
  refuseAll.mockReset();
  mocks.headers = new Headers({
    authorization: `Bearer ${await signer.sign({
      sub: "11111111-1111-4111-8111-111111111111",
    })}`,
  });
});

describe("NextOptions.actions", () => {
  it("adds the envelope to a success and types it", async () => {
    const act = bsb.action({}, () => "done" as const);
    const outcome = await act(undefined);

    expect(outcome).toEqual({
      ok: true,
      data: "done",
      error: null,
      message: "Saved",
    });
    expectTypeOf(outcome.message).toBeString();
  });

  it("adds the envelope to a refusal by the app guard and skips the body", async () => {
    refuseAll.mockReturnValue(dbError("forbidden", "Read only."));

    const body = vi.fn(() => "never");
    const outcome = await bsb.action({}, body)(undefined);

    expect(body).not.toHaveBeenCalled();
    expect(outcome).toMatchObject({ ok: false, message: "Read only." });
  });

  it("settles a value from() recognizes", async () => {
    const outcome = await bsb.action({}, () => ({ boxed: 7 }))(undefined);

    expect(outcome).toMatchObject({ ok: true, data: 7 });
  });
});
