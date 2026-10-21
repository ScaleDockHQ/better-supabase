import type * as ReactModule from "react";

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
} from "../../src/react/block-hooks.ts";
import { renderHook } from "../fixtures/hook-runtime.ts";
import { flush, resolved } from "../fixtures/ports.ts";

vi.mock("react", async (importOriginal) => ({
  ...(await importOriginal<typeof ReactModule>()),
  ...(await import("../fixtures/hook-runtime.ts")).reactHooks,
}));

const calls: string[] = [];

const tasks = {
  list(filter: { readonly status: string }): AsyncResult<readonly string[]> {
    calls.push(filter.status);

    return resolved([filter.status]);
  },
  rename(id: string, title: string): AsyncResult<string> {
    return resolved(`${id}:${title}`);
  },
};

describe("block hooks", () => {
  it("queries a block method and makes a new controller when the args change", async () => {
    calls.length = 0;

    const initial: string = "open";

    const view = renderHook(
      (status: string) => useBlockQuery(tasks, "list", [{ status }]),
      initial,
    );

    await flush();
    expect(view.result.data).toEqual(["open"]);
    view.rerender("open");
    expect(calls).toEqual(["open"]);
    view.rerender("done");
    await flush();
    expect(calls).toEqual(["open", "done"]);
    view.unmount();
  });

  it("mutates with spread arguments", async () => {
    const view = renderHook(() => useBlockMutation(tasks, "rename"), undefined);

    const renamed = await view.result.mutate("t1", "Ship");

    expect(renamed.ok && renamed.data).toBe("t1:Ship");
    view.unmount();
  });

  it("listens to block events until unmount", () => {
    const events = new EventHub();
    const seen: string[] = [];

    const view = renderHook(() => {
      useBlockEvent(
        { events },
        organizationsEvents,
        "invitation.*",
        (event) => {
          seen.push(event.type);
        },
      );
    }, undefined);

    emitBlockEvent<OrganizationsEvents>(events, "invitation.accepted", {
      invitationId: "i1",
    });
    view.unmount();
    emitBlockEvent<OrganizationsEvents>(events, "invitation.revoked", {
      invitationId: "i1",
    });
    expect(seen).toEqual(["invitation.accepted"]);
  });
});
