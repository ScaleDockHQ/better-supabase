import { describe, expect, it } from "vitest";

import type {
  MountedBinding,
  ProbeController,
} from "../../../src/testing/kits/controller-binding.ts";

import { ConformanceError } from "../../../src/testing/conformance.ts";
import {
  PROBE_INITIAL,
  testControllerBinding,
} from "../../../src/testing/kits/controller-binding.ts";

/** A binding with no framework: reads the controller while subscribed. */
function direct(options: { follow?: boolean; stop?: boolean } = {}) {
  return {
    mount: (create: () => ProbeController): MountedBinding => {
      const controller = create();
      let state = controller.getSnapshot();
      const unsubscribe = controller.subscribe(() => {
        if (options.follow ?? true) {
          state = controller.getSnapshot();
        }
      });
      return {
        read: () => state,
        actions: controller.actions,
        unmount: () => {
          if (options.stop ?? true) {
            unsubscribe();
            controller.dispose();
          }
        },
      };
    },
  };
}

const failures = async (report: Promise<unknown>): Promise<string[]> => {
  try {
    await report;
    return [];
  } catch (error) {
    if (!(error instanceof ConformanceError)) {
      throw error;
    }
    return error.report.checks
      .filter((check) => !check.ok)
      .map((check) => check.name);
  }
};

describe("testControllerBinding", () => {
  it("passes a binding that follows the controller", async () => {
    const report = await testControllerBinding("direct", direct());
    expect(report.subject).toBe('ControllerBinding "direct"');
    expect(report.checks.every((check) => check.ok)).toBe(true);
    expect(PROBE_INITIAL).toEqual({ count: 0, label: "initial" });
  });

  it("fails a binding that misses changes or never stops", async () => {
    expect(
      await failures(testControllerBinding("stale", direct({ follow: false }))),
    ).toEqual([
      "renders a change from the controller",
      "passes the controller's actions through",
    ]);
    expect(
      await failures(testControllerBinding("leaky", direct({ stop: false }))),
    ).toEqual(["stops the controller on unmount"]);
  });

  it("skips the dispose check for bindings that keep the controller", async () => {
    const binding = direct();
    const report = await testControllerBinding("kept", {
      mount: (create) => {
        const mounted = binding.mount(() => {
          const controller = create();
          return { ...controller, dispose: () => undefined };
        });
        return mounted;
      },
      disposes: false,
    });
    expect(report.checks).toHaveLength(4);
  });
});
