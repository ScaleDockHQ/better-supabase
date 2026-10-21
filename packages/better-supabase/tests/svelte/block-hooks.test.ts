import * as $ from "svelte/internal/client";
import { get } from "svelte/store";
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
} from "../../src/svelte/block-hooks.ts";
import { flush, resolved } from "../fixtures/ports.ts";

// Node resolves svelte to its server runtime, where effects never run.
vi.mock(import("svelte"), () => {
  const clientBuild = "../../node_modules/svelte/src/index-client.js";

  return import(clientBuild);
});

const tasks = {
  list(filter: { readonly status: string }): AsyncResult<readonly string[]> {
    return resolved([filter.status]);
  },
  rename(id: string, title: string): AsyncResult<string> {
    return resolved(`${id}:${title}`);
  },
};

/** Runs `setup` as a component's script, then mounts. */
function mount<T>(setup: () => T): { value: T; unmount: () => void } {
  let value: T | undefined;

  const stop = $.effect_root(() => {
    $.push({}, true);
    value = setup();
    $.pop();
  });

  $.flush();

  // SAFETY: setup ran inside the effect root.
  return { value: value as T, unmount: stop };
}

describe("block hooks (Svelte)", () => {
  it("queries a block method into a store", async () => {
    const { value, unmount } = mount(() =>
      useBlockQuery(tasks, "list", [{ status: "open" }]),
    );

    const stop = value.subscribe(() => undefined);

    await flush();
    expect(get(value).data).toEqual(["open"]);
    stop();
    unmount();
  });

  it("mutates with spread arguments", async () => {
    const { value, unmount } = mount(() => useBlockMutation(tasks, "rename"));

    const renamed = await value.actions.mutate("t1", "Ship");

    expect(renamed.ok && renamed.data).toBe("t1:Ship");
    unmount();
  });

  it("listens to block events until the component is destroyed", () => {
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
