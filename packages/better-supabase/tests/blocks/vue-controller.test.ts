import { describe, expect, it } from "vitest";
import {
  createApp,
  createSSRApp,
  defineComponent,
  effectScope,
  h,
  nextTick,
} from "vue";
import { renderToString } from "vue/server-renderer";

import type { EnvOptions } from "../fixtures/block-bindings.ts";

import { useUndoStack } from "../../src/blocks/undo/vue/index.ts";
import { useBlockController } from "../../src/blocks/vue-controller.ts";
import { testControllerBinding } from "../../src/testing/kits/controller-binding.ts";
import { betterSupabase } from "../../src/vue/index.ts";
import {
  fakeBlockClient,
  fakeEnv,
  startCounter,
} from "../fixtures/block-bindings.ts";

describe("useBlockController (Vue)", () => {
  it("passes the controller binding conformance kit", async () => {
    const env = fakeEnv();
    await testControllerBinding("vue", {
      mount: (create) => {
        const scope = effectScope();

        const bound = scope.run(() =>
          useBlockController((_options: EnvOptions) => create(), env),
        )!;

        return {
          read: () => bound.state.value,
          actions: bound.actions,
          unmount: () => {
            scope.stop();
          },
        };
      },
      settle: nextTick,
    });
  });

  it("fills auth and ports from the plugin, and needs it", () => {
    const client = fakeBlockClient();
    const app = createApp({ render: () => null });
    app.use(betterSupabase(client));
    const counter = startCounter();
    const scope = effectScope();
    app.runWithContext(() =>
      scope.run(() => useBlockController(counter.create, { label: "a" })),
    );
    expect(counter.given()).toMatchObject({ label: "a", auth: client.auth });
    expect(counter.given()?.ports.topic).toBe(client.ports?.topic);
    scope.stop();

    expect(() =>
      effectScope().run(() => useBlockController(startCounter().create, {})),
    ).toThrow(/betterSupabase\(bsb\)/);
  });

  it("starts nothing while rendering on the server", async () => {
    const counter = startCounter();

    const app = createSSRApp(
      defineComponent({
        setup() {
          const bound = useBlockController(counter.create, fakeEnv());

          return () => h("span", bound.state.value.label);
        },
      }),
    );

    expect(await renderToString(app)).toBe("<span>initial</span>");
    expect(counter.starts()).toBe(0);
  });

  it("runs a generated wrapper without a provider when its controller needs none", async () => {
    const scope = effectScope();

    const undo = scope.run(() =>
      useUndoStack({ apply: async () => undefined }),
    )!;

    undo.actions.push({ v: 1, calls: [] }, "Moved");
    await nextTick();
    expect(undo.state.value.entries.map((entry) => entry.label)).toEqual([
      "Moved",
    ]);
    scope.stop();
  });
});
