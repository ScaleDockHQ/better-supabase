import { describe, expect, it, vi } from "vitest";

import { defineBlock } from "../../src/blocks/define-block.ts";
import {
  createRecordController,
  defineRecordBinding,
} from "../../src/records/index.ts";
import {
  failed,
  fakeAuth,
  fakeTopic,
  flush,
  mount,
  resolved,
} from "../fixtures/ports.ts";

const customer = { type: "customer", id: "7" };

function setup(load = vi.fn(() => resolved(["n1"]))) {
  const notes = defineBlock({
    name: "notes",
    category: "collaboration",
    record: defineRecordBinding({
      permissions: { read: "read" },
      load: () => load(),
      events: ["note.created"],
    }),
  });

  return { load, source: { blocks: { notes }, clients: { notes: {} } } };
}

const create = (
  source: ReturnType<typeof setup>["source"],
  offline?: boolean,
) =>
  createRecordController({
    source,
    auth: fakeAuth(),
    ports: { topic: fakeTopic().port },
    subject: customer,
    bindings: ["notes"],
    ...(offline === undefined ? {} : { offline }),
  });

describe("createRecordController offline", () => {
  it("loads as usual and reports no flag until told", async () => {
    const { load, source } = setup();
    const { view, unmount } = mount(create(source));
    await flush();

    expect(load).toHaveBeenCalledOnce();
    expect(view().bindings).toEqual({ notes: { kind: "ok", data: ["n1"] } });
    expect(view().offline).toBeUndefined();
    unmount();
  });

  it("holds the first load while offline and runs it on reconnect", async () => {
    const { load, source } = setup();
    const { view, unmount } = mount(create(source, true));
    await flush();

    expect(load).not.toHaveBeenCalled();
    expect(view()).toMatchObject({ offline: true, bindings: undefined });

    view().setOffline(false);
    await flush();

    expect(load).toHaveBeenCalledOnce();
    expect(view()).toMatchObject({
      offline: false,
      bindings: { notes: { kind: "ok", data: ["n1"] } },
    });

    unmount();
  });

  it("keeps a binding's data when a refresh fails offline", async () => {
    const load = vi.fn(() => resolved(["n1"]));
    const { source } = setup(load);
    const { view, unmount } = mount(create(source));
    await flush();

    view().setOffline(true);
    load.mockReturnValue(failed("network"));
    await view().refresh(["notes"]);
    await flush();

    expect(load).toHaveBeenCalledOnce();
    expect(view().bindings).toEqual({ notes: { kind: "ok", data: ["n1"] } });

    load.mockReturnValue(resolved(["n1", "n2"]));
    view().setOffline(false);
    await flush();

    expect(view().bindings).toEqual({
      notes: { kind: "ok", data: ["n1", "n2"] },
    });

    unmount();
  });

  it("ignores a repeated value", async () => {
    const { load, source } = setup();
    const { view, unmount } = mount(create(source, true));

    view().setOffline(true);
    view().setOffline(false);
    view().setOffline(false);
    await flush();

    expect(load).toHaveBeenCalledOnce();
    unmount();
  });
});
