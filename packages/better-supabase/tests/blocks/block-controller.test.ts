import { QueryClient } from "@tanstack/query-core";
import { describe, expect, expectTypeOf, it } from "vitest";

import type { OrganizationsEvents } from "../../src/blocks/organizations/events.ts";
import type { Result } from "../../src/core/result.ts";

import {
  blockArgsKey,
  createBlockMutation,
  createBlockQuery,
  listenToBlockEvents,
} from "../../src/blocks/block-controller.ts";
import {
  createOfflineBlockMutation,
  createOfflineBlockQuery,
} from "../../src/blocks/block-offline.ts";
import { optimisticUpdate } from "../../src/blocks/optimistic.ts";
import { organizationsEvents } from "../../src/blocks/organizations/events.ts";
import { emitBlockEvent } from "../../src/core/block-events.ts";
import { dbError } from "../../src/core/errors.ts";
import { EventHub } from "../../src/core/events.ts";
import { AsyncResult, err, ok } from "../../src/core/result.ts";
import { blockControllerEngine } from "../../src/query/blocks.ts";
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

describe("offline block controllers", () => {
  it("holds a read while offline and runs it once on reconnect", async () => {
    const { client, calls } = fakeTasks();

    const query = createOfflineBlockQuery(
      client,
      "list",
      [{ status: "open" }],
      { offline: true },
    );

    const view = mount(query);
    await flush();

    expect(calls).toEqual([]);
    expect(view.view()).toMatchObject({ status: "idle", offline: true });

    query.actions.setOffline(false);
    query.actions.setOffline(false);
    await flush();

    expect(calls).toEqual(["list:open"]);
    expect(view.view()).toMatchObject({ status: "success", offline: false });
    view.unmount();
  });

  it("ignores a refetch while offline and runs it on reconnect", async () => {
    const { client, calls } = fakeTasks();
    const query = createOfflineBlockQuery(client, "list", [{ status: "open" }]);
    const view = mount(query);
    await flush();

    query.actions.setOffline(true);
    query.actions.refetch();
    await flush();
    expect(calls).toEqual(["list:open"]);

    query.actions.setOffline(false);
    await flush();
    expect(calls).toEqual(["list:open", "list:open"]);
    view.unmount();
  });

  it("keeps the last data and sets no error when the connection drops mid-read", async () => {
    let settle: (result: Result<readonly string[]>) => void = () => undefined;
    let first = true;

    const client = {
      list(): AsyncResult<readonly string[]> {
        if (first) {
          first = false;

          return resolved(["a"]);
        }

        return new AsyncResult(
          new Promise<Result<readonly string[]>>((resolve) => {
            settle = resolve;
          }),
        );
      },
    };

    const query = createOfflineBlockQuery(client, "list", []);
    const view = mount(query);
    await flush();

    query.actions.refetch();
    query.actions.setOffline(true);
    settle(err(dbError("network", "offline")));
    await flush();

    expect(view.view()).toMatchObject({
      status: "success",
      data: ["a"],
      error: undefined,
      offline: true,
    });

    query.actions.setOffline(false);
    await flush();
    expect(view.view().status).toBe("loading");
    settle(ok(["b"]));
    await flush();
    expect(view.view()).toMatchObject({ data: ["b"], status: "success" });
    view.unmount();
  });

  it("queues one write while offline and shares its promise", async () => {
    const { client, calls } = fakeTasks();

    const mutation = createOfflineBlockMutation(client, "create", {
      offline: true,
    });

    const view = mount(mutation);

    const first = mutation.actions.mutate({ title: "a" });
    const second = mutation.actions.mutate({ title: "b" });

    expect(second).toBe(first);
    expect(view.view()).toMatchObject({ status: "pending", offline: true });
    expect(calls).toEqual([]);

    mutation.actions.setOffline(false);
    const result = await first;
    await flush();

    expect(result.ok).toBe(true);
    expect(calls).toEqual(["create:b"]);
    expect(view.view()).toMatchObject({ status: "success" });
    view.unmount();
  });

  it("cancels the queued write on reset", async () => {
    const { client, calls } = fakeTasks();

    const mutation = createOfflineBlockMutation(client, "create", {
      offline: true,
    });

    const queued = mutation.actions.mutate({ title: "a" });

    mutation.actions.reset();
    mutation.actions.setOffline(false);

    const result = await queued;
    expect(result.ok).toBe(false);
    expect(calls).toEqual([]);
  });
});

describe("offline block controllers in a data engine", () => {
  const engineOptions = () =>
    ({
      engine: blockControllerEngine(new QueryClient()),
      instance: "tasks",
    }) as const;

  it("reports the flag, skips refetches and event reads while offline", async () => {
    const { client, calls } = fakeTasks();
    const events = new EventHub();

    const query = createOfflineBlockQuery(
      client,
      "list",
      [{ status: "open" }],
      {
        ...engineOptions(),
        offline: true,
        refetchOn: { source: { events }, types: ["invitation.accepted"] },
      },
    );

    const view = mount(query);
    await flush();
    expect(view.view()).toMatchObject({ offline: true });

    query.actions.refetch();

    emitBlockEvent<OrganizationsEvents>(events, "invitation.accepted", {
      invitationId: "i1",
    });

    await flush();
    const held = calls.length;

    query.actions.setOffline(false);
    query.actions.refetch();
    await flush();

    expect(view.view()).toMatchObject({ offline: false });
    expect(calls.length).toBeGreaterThanOrEqual(held);
    view.unmount();
  });

  it("runs a read again on a block event once back online", async () => {
    const { client, calls } = fakeTasks();
    const events = new EventHub();

    const query = createOfflineBlockQuery(client, "list", [{ status: "a" }], {
      refetchOn: { source: { events }, types: ["invitation.accepted"] },
    });

    const view = mount(query);
    await flush();
    const before = calls.length;

    emitBlockEvent<OrganizationsEvents>(events, "invitation.accepted", {
      invitationId: "i1",
    });

    await flush();
    expect(calls).toHaveLength(before + 1);
    view.unmount();
  });

  it("makes a write invalidate the reads of its engine instance", async () => {
    const { client, calls } = fakeTasks();
    const options = engineOptions();

    const list = createOfflineBlockQuery(
      client,
      "list",
      [{ status: "a" }],
      options,
    );

    const view = mount(list);
    await flush();
    const before = calls.length;

    await createOfflineBlockMutation(client, "create", options).actions.mutate({
      title: "x",
    });

    await flush();
    expect(calls.length).toBeGreaterThan(before);
    view.unmount();
  });
});

describe("offline types", () => {
  it("types the offline flag and setOffline", () => {
    const { client } = fakeTasks();
    const query = createOfflineBlockQuery(client, "list", [{ status: "open" }]);
    const mutation = createOfflineBlockMutation(client, "create");

    expectTypeOf(query.getSnapshot().offline).toEqualTypeOf<
      boolean | undefined
    >();
    expectTypeOf(query.actions.setOffline).toEqualTypeOf<
      (offline: boolean) => void
    >();
    expectTypeOf(mutation.actions.setOffline).toEqualTypeOf<
      (offline: boolean) => void
    >();
  });
});

describe("createBlockMutation with optimistic", () => {
  const rows: readonly Task[] = [
    { id: "t1", title: "one" },
    { id: "t2", title: "two" },
  ];

  const make = (fail: boolean) => {
    const gate = held(true as const);

    const refused = (): AsyncResult<true> =>
      AsyncResult.from<true>(async () => {
        await gate.result;

        return err(dbError("conflict", "stale"));
      });

    const client = {
      list: (): AsyncResult<readonly Task[]> => resolved(rows),
      rename: (_id: string, _title: string): AsyncResult<true> =>
        fail ? refused() : gate.result,
    };

    const options = {
      engine: blockControllerEngine(new QueryClient()),
      instance: "tasks",
      optimistic: optimisticUpdate({
        reads: ["list"],
        target: (id: string, title: string) => ({ id, patch: { title } }),
      }),
    } as const;

    return { client, options, gate };
  };

  it("shows the change before the call answers and keeps it on success", async () => {
    const { client, options, gate } = make(false);
    const list = mount(createBlockQuery(client, "list", [], options));
    await flush();

    const pending = createBlockMutation(
      client,
      "rename",
      options,
    ).actions.mutate("t1", "uno");

    expect(list.view().data?.[0]?.title).toBe("uno");

    gate.release();
    await pending;
    list.unmount();
  });

  it("puts the cached read back when the call fails", async () => {
    const { client, options, gate } = make(true);
    const list = mount(createBlockQuery(client, "list", [], options));
    await flush();

    const pending = createBlockMutation(
      client,
      "rename",
      options,
    ).actions.mutate("t1", "uno");

    expect(list.view().data?.[0]?.title).toBe("uno");

    gate.release();
    const result = await pending;

    expect(result.ok).toBe(false);
    expect(list.view().data?.[0]?.title).toBe("one");
    list.unmount();
  });
});
