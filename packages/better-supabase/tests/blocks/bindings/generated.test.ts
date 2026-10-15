import { createRoot } from "solid-js";
import * as $ from "svelte/internal/client";
import { describe, expect, it, vi } from "vitest";
import { effectScope } from "vue";

import { fakeEnv } from "../../fixtures/block-bindings.ts";
import { fakeAuth, SIGNED_OUT } from "../../fixtures/ports.ts";
import { readBlocks } from "./render.ts";

// Node resolves these to their server builds, where effects never run.
vi.mock("svelte", () => {
  const clientBuild = "../../../node_modules/svelte/src/index-client.js";
  return import(clientBuild);
});
vi.mock("solid-js", () => {
  const browserBuild = "../../../node_modules/solid-js/dist/solid.js";
  return import(browserBuild);
});

/** Any property, call or await of it gives itself back, and an await never settles. */
const stub: unknown = new Proxy(function stub() {}, {
  get: (_target, key) =>
    key === "then"
      ? () => undefined
      : key === Symbol.toPrimitive
        ? () => 0
        : stub,
  apply: () => stub,
});

/** Controller options: a signed-out session, fake ports, and the stub for the rest. */
const options = (): object => {
  const env = { ...fakeEnv(), auth: fakeAuth(SIGNED_OUT) };
  const known = new Map<PropertyKey, unknown>(Object.entries(env));
  return new Proxy(env, {
    get: (_target, key) => (known.has(key) ? known.get(key) : stub),
  });
};

interface Bound {
  readonly actions: unknown;
  readonly controller: { readonly getSnapshot: () => unknown };
}

type Hook = (options: object) => Bound;

const MOUNT = {
  vue: (hook: Hook) => {
    const scope = effectScope();
    const bound = scope.run(() => hook(options()))!;
    return {
      bound,
      unmount: () => {
        scope.stop();
      },
    };
  },
  svelte: (hook: Hook) => {
    let bound: Bound | undefined;
    const stop = $.effect_root(() => {
      $.push({}, true);
      bound = hook(options());
      $.pop();
    });
    $.flush();
    return { bound: bound!, unmount: stop };
  },
  solid: (hook: Hook) => {
    let bound: Bound | undefined;
    let unmount = (): void => undefined;
    createRoot((dispose) => {
      unmount = dispose;
      bound = hook(options());
    });
    return { bound: bound!, unmount };
  },
};

const blocks = await readBlocks();

describe.each(Object.entries(MOUNT))(
  "generated %s bindings",
  (framework, mount) => {
    it.each(blocks.map((block) => [block.block, block] as const))(
      "%s mounts and unmounts each hook",
      async (_name, block) => {
        const entry: Record<string, unknown> = await import(
          `../../../src/blocks/${block.block}/${framework}/index.ts`
        );
        for (const { hook } of block.controllers) {
          const use = entry[hook];
          expect({ hook, type: typeof use }).toEqual({
            hook,
            type: "function",
          });
          // SAFETY: the generated entry exports `hook` as a binding over a controller.
          const { bound, unmount } = mount(use as Hook);
          expect(bound.controller.getSnapshot()).toBeTypeOf("object");
          expect(bound.actions).toBeTypeOf("object");
          unmount();
        }
      },
    );
  },
);
