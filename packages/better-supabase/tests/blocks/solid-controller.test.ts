import { createRoot } from "solid-js";
import { describe, expect, it, vi } from "vitest";

import type { SolidController } from "../../src/blocks/solid-controller.ts";

import { useBlockController } from "../../src/blocks/solid-controller.ts";
import { useUndoStack } from "../../src/blocks/undo/solid/index.ts";
import { BetterSupabaseProvider } from "../../src/solid/index.ts";
import { testControllerBinding } from "../../src/testing/kits/controller-binding.ts";
import {
  fakeBlockClient,
  fakeEnv,
  startCounter,
  type EnvOptions,
} from "../fixtures/block-bindings.ts";

// Node resolves solid-js to its server build, where effects never run.
vi.mock("solid-js", () => {
  const browserBuild = "../../node_modules/solid-js/dist/solid.js";
  return import(browserBuild);
});

function mount<S, A>(
  setup: () => SolidController<S, A>,
): { bound: SolidController<S, A>; unmount: () => void } {
  let bound: SolidController<S, A> | undefined;
  let unmount = (): void => undefined;
  createRoot((dispose) => {
    unmount = dispose;
    bound = setup();
  });
  // SAFETY: createRoot ran setup synchronously.
  return { bound: bound!, unmount };
}

describe("useBlockController (Solid)", () => {
  it("passes the controller binding conformance kit", async () => {
    const env = fakeEnv();
    await testControllerBinding("solid", {
      mount: (create) => {
        const { bound, unmount } = mount(() =>
          useBlockController((_options: EnvOptions) => create(), env),
        );
        return { read: bound.state, actions: bound.actions, unmount };
      },
    });
  });

  it("fills auth and ports from the provider, and needs it", () => {
    const client = fakeBlockClient();
    const counter = startCounter();
    const { unmount } = mount(() => {
      let bound:
        | SolidController<{ readonly label: string }, object>
        | undefined;
      BetterSupabaseProvider({
        client,
        get children() {
          bound = useBlockController(counter.create, { label: "a" });
          return null;
        },
      });
      // SAFETY: the provider read its children above.
      return bound!;
    });
    expect(counter.given()).toMatchObject({ label: "a", auth: client.auth });
    expect(counter.given()?.ports.topic).toBe(client.ports?.topic);
    unmount();

    expect(() =>
      mount(() => useBlockController(startCounter().create, {})),
    ).toThrow(/BetterSupabaseProvider/);
  });

  it("runs a generated wrapper without a provider when its controller needs none", () => {
    const { bound, unmount } = mount(() =>
      useUndoStack({ apply: async () => undefined }),
    );
    bound.actions.push({ v: 1, calls: [] }, "Moved");
    expect(bound.state().entries.map((entry) => entry.label)).toEqual([
      "Moved",
    ]);
    unmount();
  });
});
