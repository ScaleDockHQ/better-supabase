import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/blocks/orders/index.ts";

import {
  createOrders,
  KITCHEN_EVENT,
  kitchenTopic,
  PREPARATION_STATES,
} from "../../../src/blocks/orders/index.ts";

const AT = "2026-10-22T10:00:00Z";

interface Call {
  readonly fn: string;
  readonly args: Readonly<Record<string, unknown>>;
}

function kitchenWith(results: Record<string, unknown>) {
  const calls: Call[] = [];

  const transport: BlockTransport = {
    call: (_schema, fn, args) => {
      calls.push({ fn, args });

      return Promise.resolve(results[fn]);
    },
  };

  return { calls, kitchen: createOrders({ transport }).kitchen };
}

const station = {
  id: "s1",
  organizationId: "o1",
  key: "grill",
  name: "Grill",
  position: 1,
  isDefault: false,
  active: true,
  productIds: ["p1"],
  createdAt: AT,
  updatedAt: AT,
};

const line = {
  lineId: "l1",
  orderId: "r1",
  stationId: "s1",
  title: "Burger",
  sku: "B",
  quantity: 2,
  position: 1,
  state: "ready",
  note: "no onions",
  queuedAt: AT,
  startedAt: AT,
  readyAt: AT,
  servedAt: null,
};

describe("orders kitchen", () => {
  it("names the Realtime topic and the states", () => {
    expect(kitchenTopic("o1")).toBe("kitchen:o1");
    expect(KITCHEN_EVENT).toBe("preparation");
    expect(PREPARATION_STATES).toEqual([
      "queued",
      "preparing",
      "ready",
      "served",
    ]);
  });

  it("saves and lists stations", async () => {
    const { calls, kitchen } = kitchenWith({
      save_kitchen_station: station,
      kitchen_stations: [station, { ...station, id: "s2", active: false }],
      delete_kitchen_station: true,
    });

    const saved = await kitchen
      .saveStation({
        organizationId: "o1",
        input: { key: "grill", name: "Grill", productIds: ["p1"] },
      })
      .orThrow();

    expect(saved.createdAt.toString()).toBe(AT);
    expect(saved.productIds).toEqual(["p1"]);
    await kitchen.saveStation({
      organizationId: "o1",
      input: { default: true, active: false },
      stationId: "s1",
    });
    expect(
      (await kitchen.stations("o1").orThrow()).map((item) => item.active),
    ).toEqual([true, false]);
    expect(await kitchen.deleteStation("s1").orThrow()).toBe(true);
    expect(calls).toEqual([
      {
        fn: "save_kitchen_station",
        args: {
          tenant: "o1",
          station: null,
          attrs: { key: "grill", name: "Grill", productIds: ["p1"] },
        },
      },
      {
        fn: "save_kitchen_station",
        args: {
          tenant: "o1",
          station: "s1",
          attrs: { default: true, active: false },
        },
      },
      { fn: "kitchen_stations", args: { tenant: "o1" } },
      { fn: "delete_kitchen_station", args: { station: "s1" } },
    ]);
  });

  it("sends, moves and bumps lines", async () => {
    const { calls, kitchen } = kitchenWith({
      send_order_to_kitchen: 3,
      set_line_preparation: line,
      bump_kitchen_ticket: "2",
    });

    expect(
      await kitchen
        .send({ orderId: "r1", notes: { l1: "no onions" } })
        .orThrow(),
    ).toBe(3);
    await kitchen.send({ orderId: "r1" });

    const moved = await kitchen
      .setState({ lineId: "l1", state: "ready" })
      .orThrow();

    expect(moved).toMatchObject({ state: "ready", note: "no onions" });
    expect(moved.readyAt?.toString()).toBe(AT);
    expect(moved).not.toHaveProperty("servedAt");
    expect(
      await kitchen.bump({ orderId: "r1", state: "served" }).orThrow(),
    ).toBe(2);
    await kitchen.bump({ orderId: "r1", state: "ready", stationId: "s1" });
    expect(calls.map((item) => item.args)).toEqual([
      { order_id: "r1", notes: { l1: "no onions" } },
      { order_id: "r1", notes: null },
      { line: "l1", state: "ready" },
      { order_id: "r1", station: null, state: "served" },
      { order_id: "r1", station: "s1", state: "ready" },
    ]);
  });

  it("reads a kitchen queue and an order board", async () => {
    const { calls, kitchen } = kitchenWith({
      kitchen_queue: [
        {
          orderId: "r1",
          number: "SO-1",
          sentAt: AT,
          lines: [{ ...line, stationId: null, note: null, state: "queued" }],
        },
      ],
      order_board: [
        {
          orderId: "r1",
          number: "SO-1",
          customerId: null,
          status: "paid",
          state: "preparing",
          sentAt: AT,
          readyAt: null,
          servedAt: null,
          counts: { queued: 1, preparing: 2, ready: 0, served: "0" },
        },
        {
          orderId: "r2",
          number: "SO-2",
          customerId: "u1",
          status: "paid",
          state: "served",
          sentAt: AT,
          readyAt: AT,
          servedAt: AT,
          counts: null,
        },
      ],
    });

    const [ticket] = await kitchen.queue({ organizationId: "o1" }).orThrow();
    expect(ticket!.lines[0]).not.toHaveProperty("stationId");
    expect(ticket!.lines[0]).not.toHaveProperty("note");
    await kitchen.queue({
      organizationId: "o1",
      query: { stationId: "s1", states: ["ready"], pageSize: 10 },
    });

    const cards = await kitchen.board({ organizationId: "o1" }).orThrow();
    expect(cards[0]).toMatchObject({
      state: "preparing",
      counts: { queued: 1, preparing: 2, ready: 0, served: 0 },
    });
    expect(cards[0]).not.toHaveProperty("customerId");
    expect(cards[1]).toMatchObject({
      customerId: "u1",
      counts: { queued: 0, preparing: 0, ready: 0, served: 0 },
    });
    expect(cards[1]!.servedAt?.toString()).toBe(AT);
    await kitchen.board({
      organizationId: "o1",
      query: { since: Temporal.Instant.from(AT), pageSize: 5 },
    });

    expect(calls.map((item) => item.args)).toEqual([
      { tenant: "o1", station: null, states: null, page_size: null },
      { tenant: "o1", station: "s1", states: ["ready"], page_size: 10 },
      { tenant: "o1", since: null, page_size: null },
      { tenant: "o1", since: AT, page_size: 5 },
    ]);
  });

  it("refuses an unknown state from the database", async () => {
    const { kitchen } = kitchenWith({
      set_line_preparation: { ...line, state: "burnt" },
    });

    expect((await kitchen.setState({ lineId: "l1", state: "ready" })).ok).toBe(
      false,
    );
  });
});
