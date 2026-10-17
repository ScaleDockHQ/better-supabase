import { createClient } from "@supabase/supabase-js";
import * as v from "valibot";
import { describe, expect, expectTypeOf, it } from "vitest";

import type { Result } from "../../src/core/result.ts";

import { functions } from "../../src/client/index.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { DbException } from "../../src/core/errors.ts";
import {
  type ContractOf,
  createEdge,
  defineFunction,
} from "../../src/edge/index.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const USER = "11111111-1111-4111-8111-111111111111";
const signer = await createTestSigner();
const bs = createEdge(defineSupabase(schema), {
  env: {
    url: PROJECT_URL,
    publishableKey: "sb_publishable_test",
    jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
  },
  auth: { jwks: signer.jwks as never },
});

const sendInvite = defineFunction(bs, {
  input: v.object({ email: v.pipe(v.string(), v.email()) }),
  output: v.object({ email: v.string(), by: v.string() }),
  handler: (input, ctx) => ({
    email: input.email,
    by: ctx.auth.kind === "user" ? ctx.auth.user.id : "nobody",
  }),
});
const echo = defineFunction(bs, {
  input: v.string(),
  handler: (input) => input.toUpperCase(),
});
const ping = defineFunction(bs, {
  input: v.optional(v.object({})),
  handler: () => undefined,
});

type Contracts = {
  "send-invite": ContractOf<typeof sendInvite>;
  echo: ContractOf<typeof echo>;
  ping: ContractOf<typeof ping>;
};

const handlers: Record<string, (request: Request) => Promise<Response>> = {
  "send-invite": sendInvite,
  echo,
  ping,
  relay: () =>
    Promise.resolve(
      new Response("relay down", {
        status: 502,
        headers: { "x-relay-error": "true" },
      }),
    ),
  plain: () => Promise.resolve(new Response("boom", { status: 500 })),
};

function client(fail?: Error) {
  return createClient(PROJECT_URL, "sb_publishable_test", {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: (input, init) => {
        if (fail) {
          return Promise.reject(fail);
        }
        const request = new Request(input, init);
        const name = new URL(request.url).pathname.split("/").at(-1) ?? "";
        const handler = handlers[name];
        return handler
          ? handler(request)
          : Promise.resolve(new Response("not found", { status: 404 }));
      },
    },
  });
}

const token = await signer.sign({ sub: USER });
const asUser = { headers: { authorization: `Bearer ${token}` } };

describe("functions()", () => {
  const fns = functions<Contracts>(client());

  it("types the input and output from the contracts", () => {
    expectTypeOf<Parameters<typeof fns.invoke>[0]>().toEqualTypeOf<
      "send-invite" | "echo" | "ping"
    >();
    void fns.invoke("ping");
    // @ts-expect-error -- send-invite needs its input
    void fns.invoke("send-invite");
    // @ts-expect-error -- email is a string
    void fns.invoke("send-invite", { email: 1 }, asUser);
  });

  it("sends the input as JSON and returns the output", async () => {
    const invite = await fns
      .invoke("send-invite", { email: "ada@acme.test" }, asUser)
      .orThrow();
    expectTypeOf(invite).toEqualTypeOf<{ email: string; by: string }>();
    expect(invite).toEqual({ email: "ada@acme.test", by: USER });

    expect(await fns.invoke("echo", "hi", asUser).orThrow()).toBe("HI");
    const pinged = await fns.invoke("ping", undefined, asUser);
    expect(pinged).toMatchObject({ ok: true, data: undefined });
  });

  it("returns the function's Problem Details as its DbError", async () => {
    const result = await fns.invoke("send-invite", { email: "nope" }, asUser);
    expect(result.ok).toBe(false);
    if (result.ok) {
      return;
    }
    expect(result.error).toMatchObject({ kind: "validation", status: 422 });

    const anonymous = await fns.invoke("send-invite", { email: "a@b.test" });
    expect(anonymous.ok ? undefined : anonymous.error.kind).toBe(
      "unauthorized",
    );
    await expect(
      fns.invoke("send-invite", { email: "nope" }, asUser).orThrow(),
    ).rejects.toBeInstanceOf(DbException);
  });

  it("maps relay, network, abort and plain HTTP failures", async () => {
    const loose =
      functions<Record<string, { input: unknown; output: unknown }>>(client());
    const kind = async (result: PromiseLike<Result<unknown>>) => {
      const settled = await result;
      return settled.ok ? undefined : settled.error.kind;
    };
    expect(await kind(loose.invoke("relay"))).toBe("network");
    expect(await kind(loose.invoke("plain"))).toBe("unexpected");
    const plain = await loose.invoke("plain");
    expect(plain.ok ? undefined : plain.error.status).toBe(500);

    const offline = functions<Contracts>(client(new TypeError("offline")));
    expect(await kind(offline.invoke("ping"))).toBe("network");

    const aborted = functions<Contracts>(
      client(new DOMException("aborted", "AbortError")),
    );
    expect(await kind(aborted.invoke("ping"))).toBe("aborted");

    const slow = functions<Contracts>(
      client(new DOMException("slow", "TimeoutError")),
    );
    expect(await kind(slow.invoke("ping"))).toBe("timeout");
  });

  it("keeps a content type the caller sets", async () => {
    const seen: string[] = [];
    const host = {
      functions: {
        invoke: (
          _name: string,
          options?: { headers?: Record<string, string> },
        ) => {
          seen.push(JSON.stringify(options?.headers));
          return Promise.resolve({ data: null, error: new Error("nope") });
        },
      },
    };
    const result = await functions<Contracts>(host).invoke("echo", "x", {
      headers: { "Content-Type": "text/plain" },
    });
    expect(seen).toEqual(['{"Content-Type":"text/plain"}']);
    expect(result.ok ? undefined : result.error).toMatchObject({
      kind: "unexpected",
      message: "nope",
    });
  });
});
