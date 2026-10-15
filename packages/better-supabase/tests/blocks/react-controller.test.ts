import type * as ReactModule from "react";

import { describe, expect, it, vi } from "vitest";

import { defineController } from "../../src/blocks/controller.ts";
import { useController } from "../../src/blocks/react-controller.ts";
import { useBlockEnv } from "../../src/blocks/react-env.ts";
import {
  BetterSupabaseProvider,
  type ClientLike,
} from "../../src/react/hooks.ts";
import { testControllerBinding } from "../../src/testing/kits/controller-binding.ts";
import { renderHook } from "../fixtures/hook-runtime.ts";
import { fakeAuth, fakeTopic } from "../fixtures/ports.ts";

vi.mock("react", async (importOriginal) => ({
  ...(await importOriginal<typeof ReactModule>()),
  ...(await import("../fixtures/hook-runtime.ts")).reactHooks,
}));

const client = (ports?: ClientLike["ports"]) =>
  // SAFETY: useBlockEnv reads only `supabase`, `auth` and `ports`.
  ({
    supabase: { name: "supabase" },
    auth: fakeAuth(),
    ports,
  }) as unknown as ClientLike;

describe("useBlockEnv", () => {
  it("needs the provider", () => {
    expect(() => renderHook(useBlockEnv, undefined)).toThrow(
      /BetterSupabaseProvider/,
    );
  });

  it("keeps the client's ports and defaults the topic port", () => {
    const topic = fakeTopic();
    const own = client({ topic: topic.port });
    const view = renderHook(useBlockEnv, undefined, () => {
      BetterSupabaseProvider({ client: own });
    });
    expect(view.result.ports.topic).toBe(topic.port);
    expect(view.result.auth).toBe(own.auth);
    view.unmount();

    const bare = renderHook(useBlockEnv, undefined, () => {
      BetterSupabaseProvider({ client: client() });
    });
    expect(typeof bare.result.ports.topic).toBe("function");
    bare.unmount();
  });
});

describe("useController", () => {
  it("renders the snapshot with the actions and makes a new controller per deps", () => {
    const made = vi.fn();
    const view = renderHook<
      string,
      { label: string; count: number; add: () => void }
    >(
      (label) =>
        useController(() => {
          made(label);
          return defineController({ label, count: 0 }, (state) => ({
            actions: {
              add: () => {
                state.set((current) => ({ count: current.count + 1 }));
              },
            },
          }));
        }, [label]).view,
      "a",
    );
    view.result.add();
    expect(view.result).toMatchObject({ label: "a", count: 1 });
    view.rerender("a");
    expect(made).toHaveBeenCalledTimes(1);
    view.rerender("b");
    expect(view.result).toMatchObject({ label: "b", count: 0 });
    view.unmount();
  });
});

describe("useController conformance", () => {
  it("passes the controller binding conformance kit", async () => {
    await testControllerBinding("react", {
      mount: (create) => {
        const view = renderHook(
          () => useController(create, []).view,
          undefined,
        );
        return {
          read: () => view.result,
          actions: view.result,
          unmount: () => {
            view.unmount();
          },
        };
      },
      // StrictMode mounts twice, so the hook stops the work and keeps the controller.
      disposes: false,
    });
  });
});
