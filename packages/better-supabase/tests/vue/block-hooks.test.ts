import { describe, expect, it } from "vitest";
import { effectScope } from "vue";

import type { OrganizationsEvents } from "../../src/blocks/organizations/events.ts";
import type { AsyncResult } from "../../src/core/result.ts";

import { organizationsEvents } from "../../src/blocks/organizations/events.ts";
import { emitBlockEvent } from "../../src/core/block-events.ts";
import { EventHub } from "../../src/core/events.ts";
import {
  useBlockEvent,
  useBlockMutation,
  useBlockQuery,
} from "../../src/vue/block-hooks.ts";
import { flush, resolved } from "../fixtures/ports.ts";

const tasks = {
  list(filter: { readonly status: string }): AsyncResult<readonly string[]> {
    return resolved([filter.status]);
  },
  rename(id: string, title: string): AsyncResult<string> {
    return resolved(`${id}:${title}`);
  },
};

describe("block hooks (Vue)", () => {
  it("queries a block method into a ref", async () => {
    const scope = effectScope();

    const bound = scope.run(() =>
      useBlockQuery(tasks, "list", [{ status: "open" }]),
    )!;

    await flush();
    expect(bound.state.value.data).toEqual(["open"]);
    scope.stop();
  });

  it("mutates with spread arguments", async () => {
    const scope = effectScope();
    const bound = scope.run(() => useBlockMutation(tasks, "rename"))!;

    const renamed = await bound.actions.mutate("t1", "Ship");

    expect(renamed.ok && renamed.data).toBe("t1:Ship");
    expect(bound.state.value.data).toBe("t1:Ship");
    scope.stop();
  });

  it("listens to block events until the scope stops", () => {
    const events = new EventHub();
    const seen: string[] = [];
    const scope = effectScope();

    scope.run(() => {
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
    scope.stop();
    emitBlockEvent<OrganizationsEvents>(events, "invitation.revoked", {
      invitationId: "i1",
    });
    expect(seen).toEqual(["invitation.accepted"]);
  });
});
