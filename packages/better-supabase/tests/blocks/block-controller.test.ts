import { describe, expect, expectTypeOf, it } from "vitest";

import type { OrganizationsEvents } from "../../src/blocks/organizations/events.ts";
import type { AsyncResult } from "../../src/core/result.ts";

import {
  blockArgsKey,
  createBlockMutation,
  createBlockQuery,
  listenToBlockEvents,
} from "../../src/blocks/block-controller.ts";
import { organizationsEvents } from "../../src/blocks/organizations/events.ts";
import { emitBlockEvent } from "../../src/core/block-events.ts";
import { EventHub } from "../../src/core/events.ts";
import { failed, flush, held, mount, resolved } from "../fixtures/ports.ts";

interface Task {
  readonly id: string;
  readonly title: string;
}

function fakeTasks(): {
  readonly client: {
    list(filter: { readonly status: string }): AsyncResult<readonly Task[]>;
    create(input: { readonly title: string }): AsyncResult<Task>;
  };
  readonly calls: string[];
} {
  const calls: string[] = [];

  return {
    calls,
    client: {
      list(filter) {
        calls.push(`list:${filter.status}`);

        return resolved([{ id: "t1", title: filter.status }]);
      },
      create(input) {
        calls.push(`create:${input.title}`);

        return input.title === ""
          ? failed("empty title")
          : resolved({ id: "t2", title: input.title });
      },
    },
  };
}

describe("createBlockQuery", () => {
  it("loads when the first listener subscribes and types the data", async () => {
    const { client, calls } = fakeTasks();
    const query = createBlockQuery(client, "list", [{ status: "open" }]);

    expect(calls).toEqual([]);

    const mounted = mount(query);

    expect(mounted.view().status).toBe("loading");
    await flush();
    expect(mounted.view()).toMatchObject({
      status: "success",
      data: [{ id: "t1", title: "open" }],
    });
    expectTypeOf(mounted.view().data).toEqualTypeOf<
      readonly Task[] | undefined
    >();
    mounted.unmount();
  });

  it("refetches on the block events it names, until it stops", async () => {
    const { client, calls } = fakeTasks();
    const events = new EventHub();

    const mounted = mount(
      createBlockQuery(client, "list", [{ status: "open" }], {
        refetchOn: { source: { events }, types: ["invitation.accepted"] },
      }),
    );

    await flush();
    emitBlockEvent<OrganizationsEvents>(events, "invitation.revoked", {
      invitationId: "i1",
    });
    emitBlockEvent<OrganizationsEvents>(events, "invitation.accepted", {
      invitationId: "i1",
    });
    await flush();
    expect(calls).toEqual(["list:open", "list:open"]);
    mounted.unmount();
    emitBlockEvent<OrganizationsEvents>(events, "invitation.accepted", {
      invitationId: "i1",
    });
    expect(calls).toHaveLength(2);
  });

  it("drops an answer that arrives after it stopped", async () => {
    const pending = held<readonly Task[]>([]);
    const client = { list: (): AsyncResult<readonly Task[]> => pending.result };
    const query = createBlockQuery(client, "list", []);
    const mounted = mount(query);

    mounted.unmount();
    pending.release();
    await flush();
    expect(query.getSnapshot().status).not.toBe("success");
  });

  it("refuses a method the client does not have", () => {
    const { client } = fakeTasks();

    expect(() =>
      // @ts-expect-error: the client has no `remove`
      createBlockQuery(client, "remove", []),
    ).toThrow(TypeError);
  });
});

describe("createBlockMutation", () => {
  it("tracks the latest call and returns its result", async () => {
    const { client } = fakeTasks();
    const mutation = createBlockMutation(client, "create");
    const mounted = mount(mutation);

    const created = await mounted.view().mutate({ title: "Ship" });

    expect(created.ok).toBe(true);
    expect(mounted.view()).toMatchObject({
      status: "success",
      data: { id: "t2", title: "Ship" },
    });

    await mounted.view().mutate({ title: "" });
    expect(mounted.view().status).toBe("error");
    expect(mounted.view().error?.kind).toBe("not_found");
    mounted.view().reset();
    expect(mounted.view().status).toBe("idle");
    mounted.unmount();
  });
});

describe("helpers", () => {
  it("keys arguments, bigints included", () => {
    expect(blockArgsKey([{ a: 1n }, "x"])).toBe('[{"a":"1n"},"x"]');
  });

  it("listens to matching block events with the latest handler", () => {
    const events = new EventHub();
    const seen: string[] = [];

    let handler = (event: { readonly type: string }): void => {
      seen.push(`first:${event.type}`);
    };

    const stop = listenToBlockEvents(
      { events },
      organizationsEvents,
      "invitation.*",
      () => handler,
    );

    emitBlockEvent<OrganizationsEvents>(events, "invitation.accepted", {
      invitationId: "i1",
    });

    handler = (event) => {
      seen.push(`second:${event.type}`);
    };

    emitBlockEvent<OrganizationsEvents>(events, "invitation.revoked", {
      invitationId: "i1",
    });
    emitBlockEvent<OrganizationsEvents>(events, "organization.created", {
      organizationId: "o1",
    });
    stop();
    emitBlockEvent<OrganizationsEvents>(events, "invitation.accepted", {
      invitationId: "i1",
    });
    expect(seen).toEqual([
      "first:invitation.accepted",
      "second:invitation.revoked",
    ]);
  });
});
