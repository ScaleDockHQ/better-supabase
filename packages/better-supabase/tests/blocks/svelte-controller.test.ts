import * as $ from "svelte/internal/client";
import { describe, expect, it, vi } from "vitest";

import type { SvelteController } from "../../src/blocks/svelte-controller.ts";

import { useBlockController } from "../../src/blocks/svelte-controller.ts";
import { useUndoStack } from "../../src/blocks/undo/svelte/index.ts";
import { setBetterSupabase } from "../../src/svelte/index.ts";
import { testControllerBinding } from "../../src/testing/kits/controller-binding.ts";
import {
  fakeBlockClient,
  fakeEnv,
  startCounter,
  type EnvOptions,
} from "../fixtures/block-bindings.ts";

// Node resolves svelte to its server runtime, where effects never run.
vi.mock("svelte", () => {
  const clientBuild = "../../node_modules/svelte/src/index-client.js";

  return import(clientBuild);
});

vi.mock("svelte/reactivity", () => {
  const clientBuild =
    "../../node_modules/svelte/src/reactivity/index-client.js";

  return import(clientBuild);
});

/**
 * Runs `setup` as a component's script, reads the store as its template
 * would, then mounts. `unmount` destroys the component.
 */
function mount<S, A>(
  setup: () => SvelteController<S, A>,
  parent?: () => void,
): { bound: SvelteController<S, A>; read: () => S; unmount: () => void } {
  let bound: SvelteController<S, A> | undefined;
  let last: S | undefined;
  let unsubscribe = (): void => undefined;

  const stop = $.effect_root(() => {
    $.push({}, true);
    parent?.();
    bound = setup();
    unsubscribe = bound.subscribe((value) => {
      last = value;
    });
    $.pop();
  });

  $.flush();

  return {
    // SAFETY: setup ran inside the effect root.
    bound: bound!,
    // SAFETY: a readable store calls its subscriber at once.
    read: () => last as S,
    unmount: () => {
      unsubscribe();
      stop();
    },
  };
}

describe("useBlockController (Svelte)", () => {
  it("passes the controller binding conformance kit", async () => {
    const env = fakeEnv();
    await testControllerBinding("svelte", {
      mount: (create) => {
        const mounted = mount(() =>
          useBlockController((_options: EnvOptions) => create(), env),
        );

        return {
          read: mounted.read,
          actions: mounted.bound.actions,
          unmount: mounted.unmount,
        };
      },
      settle: () => {
        $.flush();
      },
    });
  });

  it("fills auth and ports from setBetterSupabase, and needs it", () => {
    const client = fakeBlockClient();
    const counter = startCounter();

    const mounted = mount(
      () => useBlockController(counter.create, { label: "a" }),
      () => void setBetterSupabase(client),
    );

    expect(counter.given()).toMatchObject({ label: "a", auth: client.auth });
    expect(counter.given()?.ports.topic).toBe(client.ports?.topic);
    mounted.unmount();

    expect(() =>
      mount(() => useBlockController(startCounter().create, {})),
    ).toThrow(/setBetterSupabase\(bs\)/);
  });

  it("starts nothing until the component mounts", () => {
    const counter = startCounter();
    let started = -1;

    const stop = $.effect_root(() => {
      $.push({}, true);
      const bound = useBlockController(counter.create, fakeEnv());
      bound.subscribe(() => undefined);
      started = counter.starts();
      $.pop();
    });

    expect(started).toBe(0);
    $.flush();
    expect(counter.starts()).toBe(1);
    stop();
  });

  it("runs a generated wrapper without a provider when its controller needs none", () => {
    const mounted = mount(() => useUndoStack({ apply: async () => undefined }));
    mounted.bound.actions.push({ v: 1, calls: [] }, "Moved");
    expect(mounted.read().entries.map((entry) => entry.label)).toEqual([
      "Moved",
    ]);
    mounted.unmount();
  });
});
