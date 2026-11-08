import type { ReactElement } from "react";

import { createElement } from "react";
import { renderToReadableStream } from "react-dom/server";
import { beforeEach, describe, expect, expectTypeOf, it, vi } from "vitest";

import type { GateUser } from "../../../src/next/index.ts";

import { createSupabase } from "../../../src/core/define.ts";
import { AuthGate, useUser } from "../../../src/next/auth-gate/index.ts";
import { createNext } from "../../../src/next/index.ts";
import { createTestSigner } from "../../../src/testing/jwt.ts";
import { schema } from "../../fixtures/generated-camel.ts";

const mocks = vi.hoisted(() => ({
  headers: new Headers(),
  cacheLife: vi.fn<(profile: unknown) => void>(),
}));

vi.mock(import("next/headers.js"), () => ({
  // SAFETY: the code under test reads only getAll from the cookie jar.
  cookies: () => Promise.resolve({ getAll: () => [] } as never),
  headers: () => Promise.resolve(mocks.headers as never),
}));

vi.mock(import("next/cache.js"), () => ({
  cacheLife: mocks.cacheLife,
  cacheTag: vi.fn(),
  updateTag: vi.fn(),
  revalidateTag: vi.fn(),
  io: () => Promise.resolve(),
}));

const PROJECT_URL = "https://abcdefghijklmnopqrst.supabase.co";
const USER = "11111111-1111-4111-8111-111111111111";
const signer = await createTestSigner();

const bsb = createNext(createSupabase(schema), {
  env: {
    url: PROJECT_URL,
    publishableKey: "sb_publishable_test",
    jwksUrl: new URL(`${PROJECT_URL}/auth/v1/.well-known/jwks.json`),
  },
  cacheTags: false,
  auth: { jwks: signer.jwks },
});

const ada: GateUser = {
  id: USER,
  email: "ada@example.com",
  name: "Ada",
  organizationId: null,
};

/** The inner async component `AuthGate` puts inside its `<Suspense>`. */
async function inner(element: ReactElement): Promise<unknown> {
  const gate = (element.props as { children: ReactElement }).children;
  // SAFETY: the gate's child is its own async function component.
  const run = gate.type as (props: unknown) => Promise<unknown>;

  return run(gate.props);
}

beforeEach(() => {
  mocks.cacheLife.mockReset();
});

describe("bsb.user()", () => {
  it("returns the user as plain data, with no token", async () => {
    const token = await signer.sign({
      sub: USER,
      email: "ada@example.com",
      user_metadata: { full_name: "Ada" },
    });

    mocks.headers = new Headers({ authorization: `Bearer ${token}` });

    const user = await bsb.user();

    expect(user).toEqual({ ...ada, organizationId: null });
    expect(JSON.stringify(user)).not.toContain(token);
    expect(mocks.cacheLife).toHaveBeenLastCalledWith({ stale: 300 });
  });

  it("returns null without a session", async () => {
    mocks.headers = new Headers();

    expect(await bsb.user()).toBeNull();
  });

  it("has no token field in its type", () => {
    expectTypeOf<
      Awaited<ReturnType<typeof bsb.user>>
    >().toEqualTypeOf<GateUser | null>();
    expectTypeOf<keyof GateUser>().toEqualTypeOf<
      "id" | "email" | "name" | "organizationId"
    >();
    expectTypeOf(useUser).returns.toEqualTypeOf<GateUser | null>();
  });
});

describe("AuthGate", () => {
  it("wraps the children in one Suspense with the fallback", async () => {
    const element = (await AuthGate({
      user: () => Promise.resolve(ada),
      fallback: "loading",
      children: "page",
    })) as ReactElement;

    expect(String(element.type)).toContain("suspense");
    expect((element.props as { fallback: unknown }).fallback).toBe("loading");
  });

  it("runs check before the first Suspense", async () => {
    const check = vi.fn(() => {
      throw new Error("refused");
    });

    await expect(
      AuthGate({ user: () => Promise.resolve(ada), children: "x", check }),
    ).rejects.toThrow("refused");
  });

  it("keys the subtree on the user id", async () => {
    const element = (await AuthGate({
      user: () => Promise.resolve(ada),
      children: "page",
    })) as ReactElement;

    const subtree = (await inner(element)) as ReactElement;

    expect(subtree.key).toBe(USER);
  });

  it("redirects a signed-out visitor", async () => {
    const element = (await AuthGate({
      user: () => Promise.resolve(null),
      children: "page",
      redirect: "/sign-in",
    })) as ReactElement;

    await expect(inner(element)).rejects.toMatchObject({
      digest: expect.stringContaining("/sign-in"),
    });
  });

  it("renders nothing for a signed-out visitor without a redirect", async () => {
    const element = (await AuthGate({
      user: () => Promise.resolve(null),
      children: "page",
    })) as ReactElement;

    expect(await inner(element)).toBeNull();
  });

  it("hands the user to useUser in a client leaf", async () => {
    function Leaf() {
      return createElement("p", null, useUser()?.email ?? "none");
    }

    const element = (await AuthGate({
      user: () => Promise.resolve(ada),
      children: createElement(Leaf),
    })) as ReactElement;

    const subtree = (await inner(element)) as ReactElement;
    const stream = await renderToReadableStream(subtree);
    await stream.allReady;

    expect(await new Response(stream).text()).toContain("ada@example.com");
  });
});

describe("AuthGate refusals", () => {
  it.each(["forbidden", "unauthorized"] as const)(
    "answers a signed-out visitor with %s()",
    async (refuse) => {
      const element = (await AuthGate({
        user: () => Promise.resolve(null),
        children: "page",
        refuse,
      })) as ReactElement;

      await expect(inner(element)).rejects.toThrow("authInterrupts");
    },
  );
});

describe("useUser", () => {
  it("throws without a gate above it", async () => {
    function Leaf() {
      return createElement("p", null, useUser()?.id ?? "none");
    }

    await expect(renderToReadableStream(createElement(Leaf))).rejects.toThrow(
      "needs an <AuthGate>",
    );
  });
});

describe("bsb.user() names", () => {
  it.each([
    [{ name: "Grace" }, "Grace"],
    [{ display_name: "Hopper" }, "Hopper"],
    [{ full_name: "" }, null],
    [{}, null],
  ])("reads %o as %s", async (metadata, expected) => {
    mocks.headers = new Headers({
      authorization: `Bearer ${await signer.sign({ sub: USER, user_metadata: metadata })}`,
    });

    expect((await bsb.user())?.name).toBe(expected);
  });
});
