import { describe, expect, it, vi } from "vitest";

import {
  defineController,
  whileSignedIn,
} from "../../src/blocks/controller.ts";
import {
  fakeAuth,
  OTHER,
  SIGNED_OUT,
  signedIn,
  USER,
} from "../fixtures/ports.ts";

function counter() {
  const start = vi.fn();
  const stop = vi.fn();
  const controller = defineController({ count: 0, label: "a" }, (state) => ({
    actions: {
      add: () => {
        state.set((current) => ({ count: current.count + 1 }));
      },
      label: (label: string) => {
        state.set({ label });
      },
      run: state.run,
    },
    start: () => {
      start();
      return stop;
    },
  }));
  return { controller, start, stop };
}

describe("defineController", () => {
  it("starts with the first listener and stops after the last", () => {
    const { controller, start, stop } = counter();
    expect(start).not.toHaveBeenCalled();
    const first = vi.fn();
    const second = vi.fn();
    const leaveFirst = controller.subscribe(first);
    const leaveSecond = controller.subscribe(second);
    expect(start).toHaveBeenCalledTimes(1);
    controller.actions.add();
    expect(first).toHaveBeenCalledTimes(1);
    expect(second).toHaveBeenCalledTimes(1);
    expect(controller.getSnapshot().count).toBe(1);
    leaveFirst();
    leaveFirst();
    expect(stop).not.toHaveBeenCalled();
    leaveSecond();
    expect(stop).toHaveBeenCalledTimes(1);
    controller.subscribe(first)();
    expect(start).toHaveBeenCalledTimes(2);
  });

  it("keeps the snapshot and tells no one when nothing changed", () => {
    const { controller } = counter();
    const listener = vi.fn();
    controller.subscribe(listener);
    const before = controller.getSnapshot();
    controller.actions.label("a");
    expect(controller.getSnapshot()).toBe(before);
    expect(listener).not.toHaveBeenCalled();
    controller.actions.label("b");
    expect(controller.getSnapshot()).not.toBe(before);
    expect(controller.getSnapshot()).toEqual({ count: 0, label: "b" });
  });

  it("moves the run on every start and stop", () => {
    const { controller } = counter();
    const idle = controller.actions.run();
    const leave = controller.subscribe(() => undefined);
    const running = controller.actions.run();
    expect(running).not.toBe(idle);
    leave();
    expect(controller.actions.run()).not.toBe(running);
  });

  it("stays idle after dispose", () => {
    const { controller, start, stop } = counter();
    const listener = vi.fn();
    controller.subscribe(listener);
    controller.dispose();
    controller.dispose();
    expect(stop).toHaveBeenCalledTimes(1);
    controller.actions.add();
    expect(listener).not.toHaveBeenCalled();
    controller.subscribe(listener)();
    expect(start).toHaveBeenCalledTimes(1);
  });

  it("works without a start", () => {
    const controller = defineController({ n: 1 }, () => ({ actions: {} }));
    controller.subscribe(() => undefined)();
    expect(controller.getSnapshot()).toEqual({ n: 1 });
  });
});

describe("whileSignedIn", () => {
  it("runs for each user and cleans up between them", () => {
    const auth = fakeAuth(SIGNED_OUT);
    const cleanup = vi.fn();
    const effect = vi.fn((_user: string) => cleanup);
    const stop = whileSignedIn(auth, effect);
    expect(effect).not.toHaveBeenCalled();
    auth.set(signedIn(USER));
    expect(effect).toHaveBeenLastCalledWith(USER);
    auth.set(signedIn(USER));
    expect(effect).toHaveBeenCalledTimes(1);
    auth.set(signedIn(OTHER));
    expect(cleanup).toHaveBeenCalledTimes(1);
    expect(effect).toHaveBeenLastCalledWith(OTHER);
    auth.set(SIGNED_OUT);
    expect(cleanup).toHaveBeenCalledTimes(2);
    auth.set(signedIn(USER));
    stop();
    expect(cleanup).toHaveBeenCalledTimes(3);
    expect(auth.listeners()).toBe(0);
  });

  it("accepts an effect without a cleanup", () => {
    const auth = fakeAuth();
    const stop = whileSignedIn(auth, () => undefined);
    auth.set(SIGNED_OUT);
    stop();
  });
});
