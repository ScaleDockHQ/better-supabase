import { describe, expect, it, vi } from "vitest";

import { withContextFactory } from "../../src/next/with-context.ts";

// SAFETY: the factory only forwards what the stub `next` returns.
const stub = (value: unknown): never => value as never;

describe("withContextFactory", () => {
  const session = { id: "s" };
  const ctx = { session };

  const next = stub({
    cached: vi.fn(async () => ctx),
    getAccess: vi.fn(async () => ({ context: ctx, session, other: 1 })),
    action: vi.fn((_options: unknown, fn: (...a: unknown[]) => unknown) =>
      fn("input", ctx, "bound"),
    ),
  });

  it("builds the extra once per base context and shares it", async () => {
    const factory = vi.fn(() => ({ extra: "x" }));
    const contextual = withContextFactory(next, factory, () => stub(session));

    const cached = await contextual.cached();
    const access = await contextual.getAccess(stub({}));

    expect(cached).toMatchObject({ extra: "x" });
    expect(access).toMatchObject({ other: 1 });
    expect(access.context).toMatchObject({ extra: "x" });
    expect(factory).toHaveBeenCalledOnce();
  });

  it("gives an action the contextual context", () => {
    const factory = vi.fn(() => ({ extra: "y" }));
    const contextual = withContextFactory(next, factory, () => stub(session));

    const fn = vi.fn((input: unknown, c: unknown, bound: unknown) => [
      input,
      c,
      bound,
    ]);

    const result = contextual.action(stub({}), stub(fn));

    expect(fn).toHaveBeenCalledWith(
      "input",
      expect.objectContaining({ extra: "y" }),
      "bound",
    );
    expect(result).toBeDefined();
  });
});
