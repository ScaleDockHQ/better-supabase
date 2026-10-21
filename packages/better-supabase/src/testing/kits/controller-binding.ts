import type { Controller } from "../../blocks/controller.ts";
import type { ConformanceReport } from "../conformance.ts";

import { defineController } from "../../blocks/controller.ts";
import { conform, expect } from "../conformance.ts";

/** The state of the probe controller a binding is tested over. */
export interface ProbeSnapshot {
  readonly count: number;
  readonly label: string;
}

export interface ProbeActions {
  readonly increment: () => void;
  readonly rename: (label: string) => void;
}

export type ProbeController = Controller<ProbeSnapshot, ProbeActions>;

/** A binding mounted over one controller, the way a component uses it. */
export interface MountedBinding {
  /** The state the binding renders now. */
  readonly read: () => ProbeSnapshot;
  /** The actions the binding hands the component. */
  readonly actions: ProbeActions;
  readonly unmount: () => void | Promise<void>;
}

export interface ControllerBindingHarness {
  /**
   * Mounts the binding over the controller `create` returns, as a component
   * would.
   */
  readonly mount: (
    create: () => ProbeController,
  ) => MountedBinding | Promise<MountedBinding>;
  /** Lets the framework apply pending updates: a tick, a flush. */
  readonly settle?: () => void | Promise<void>;
  /**
   * Whether unmounting disposes the controller. React keeps it for StrictMode's
   * second mount and only stops its work. Default true.
   */
  readonly disposes?: boolean;
}

interface Probe {
  readonly create: () => ProbeController;
  /** A change from outside the component, such as a realtime message. */
  readonly emit: (patch: Partial<ProbeSnapshot>) => void;
  readonly starts: () => number;
  readonly stops: () => number;
  readonly disposed: () => boolean;
  readonly controller: () => ProbeController | undefined;
}

export const PROBE_INITIAL: ProbeSnapshot = { count: 0, label: "initial" };

function probe(): Probe {
  let starts = 0;
  let stops = 0;
  let disposed = false;
  let made: ProbeController | undefined;
  const idle = (): void => undefined;
  let emit: (patch: Partial<ProbeSnapshot>) => void = idle;

  return {
    create: () => {
      const controller = defineController<ProbeSnapshot, ProbeActions>(
        PROBE_INITIAL,
        (state) => ({
          actions: {
            increment: () => {
              state.set((current) => ({ count: current.count + 1 }));
            },
            rename: (label) => {
              state.set({ label });
            },
          },
          start: () => {
            starts += 1;
            emit = (patch) => {
              state.set(patch);
            };

            return () => {
              stops += 1;
              emit = idle;
            };
          },
        }),
      );

      made = {
        ...controller,
        dispose: () => {
          disposed = true;
          controller.dispose();
        },
      };

      return made;
    },
    emit: (patch) => {
      emit(patch);
    },
    starts: () => starts,
    stops: () => stops,
    disposed: () => disposed,
    controller: () => made,
  };
}

/**
 * Proves a framework binding over a block controller renders the initial
 * snapshot, follows each change, passes the actions through and stops the
 * controller's work (and disposes it) on unmount.
 */
export function testControllerBinding(
  name: string,
  harness: ControllerBindingHarness,
): Promise<ConformanceReport> {
  const settle = async (): Promise<void> => {
    await harness.settle?.();
  };

  const mounted = async (
    run: (binding: MountedBinding, probe: Probe) => void | Promise<void>,
  ): Promise<void> => {
    const current = probe();
    const binding = await harness.mount(current.create);

    try {
      await settle();
      await run(binding, current);
    } finally {
      await binding.unmount();
    }
  };

  return conform(`ControllerBinding "${name}"`, [
    [
      "renders the initial snapshot",
      () =>
        mounted((binding, current) => {
          const state = binding.read();
          expect(
            state.count === PROBE_INITIAL.count &&
              state.label === PROBE_INITIAL.label,
            `rendered ${JSON.stringify(state)} instead of the initial snapshot`,
          );
          expect(
            current.starts() === 1,
            `the controller started ${current.starts()} times on mount, not once`,
          );
        }),
    ],
    [
      "renders a change from the controller",
      () =>
        mounted(async (binding, current) => {
          current.emit({ label: "changed" });
          await settle();
          expect(
            binding.read().label === "changed",
            `rendered label ${JSON.stringify(binding.read().label)} after the controller changed it`,
          );
          current.emit({ count: 5 });
          await settle();
          expect(
            binding.read().count === 5,
            `rendered count ${binding.read().count} after a second change`,
          );
        }),
    ],
    [
      "passes the controller's actions through",
      () =>
        mounted(async (binding, current) => {
          expect(
            binding.actions.increment ===
              current.controller()?.actions.increment,
            "the binding's actions are not the controller's",
          );
          binding.actions.increment();
          binding.actions.rename("renamed");
          await settle();
          const state = binding.read();
          expect(
            state.count === 1 && state.label === "renamed",
            `rendered ${JSON.stringify(state)} after the actions ran`,
          );
        }),
    ],
    [
      "stops the controller on unmount",
      async () => {
        const current = probe();
        const binding = await harness.mount(current.create);
        await settle();
        await binding.unmount();
        await settle();
        expect(
          current.stops() === current.starts() && current.starts() > 0,
          `the controller started ${current.starts()} times and stopped ${current.stops()} times`,
        );

        if (harness.disposes ?? true) {
          expect(current.disposed(), "unmount didn't dispose the controller");
        }

        current.emit({ count: 9 });
        await settle();
      },
    ],
  ]);
}
