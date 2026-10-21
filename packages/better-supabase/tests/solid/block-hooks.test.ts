import { createRoot } from "solid-js";
import { describe, expect, it, vi } from "vitest";

import type { OrganizationsEvents } from "../../src/blocks/organizations/events.ts";
import type { AsyncResult } from "../../src/core/result.ts";

import { organizationsEvents } from "../../src/blocks/organizations/events.ts";
import { emitBlockEvent } from "../../src/core/block-events.ts";
import { EventHub } from "../../src/core/events.ts";
import {
  useBlockEvent,
  useBlockMutation,
  useBlockQuery,
} from "../../src/solid/block-hooks.ts";
import { flush, resolved } from "../fixtures/ports.ts";

// Node resolves solid-js to its server build, where effects never run.
vi.mock(import("solid-js"), () => {
  const browserBuild = "../../node_modules/solid-js/dist/solid.js";

  return import(browserBuild);
});

const tasks = {
  list(filter: { readonly status: string }): AsyncResult<readonly string[]> {
    return resolved([filter.status]);
  },
  rename(id: string, title: string): AsyncResult<string> {
    return resolved(`${id}:${title}`);
  },
};

function mount<T>(setup: () => T): { value: T; unmount: () => void } {
  let value: T | undefined;
  let unmount = (): void => undefined;
  createRoot((dispose) => {
    unmount = dispose;
    value = setup();
  });

  // SAFETY: createRoot ran setup synchronously.
  return { value: value as T, unmount };
}

describe("block hooks (Solid)", () => {
  it("queries a block method into an accessor", async () => {
    const { value, unmount } = mount(() =>
      useBlockQuery(tasks, "list", [{ status: "open" }]),
    );

    await flush();
    expect(value.state().data).toEqual(["open"]);
    unmount();
  });

  it("mutates with spread arguments", async () => {
    const { value, unmount } = mount(() => useBlockMutation(tasks, "rename"));

    const renamed = await value.actions.mutate("t1", "Ship");

    expect(renamed.ok && renamed.data).toBe("t1:Ship");
    unmount();
  });

  it("listens to block events until the owner is disposed", () => {
    const events = new EventHub();
    const seen: string[] = [];

    const { unmount } = mount(() => {
      useBlockEvent(
        { events },
        organizationsEvents,
        "invitation.*",
        (event) => {
          seen.push(event.type);
        },
      );
    });

    emitBlockEvent<OrganizationsEvents>(events, "invitation.accepted", {
      invitationId: "i1",
    });
    unmount();
    emitBlockEvent<OrganizationsEvents>(events, "invitation.revoked", {
      invitationId: "i1",
    });
    expect(seen).toEqual(["invitation.accepted"]);
  });
});
