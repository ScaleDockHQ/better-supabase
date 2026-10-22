import { describe, expect, it } from "vitest";

import type { Conversation } from "../../src/blocks/inbox/types.ts";
import type { FlowEvent, FlowRef } from "../../src/flows/index.ts";

import { dbError } from "../../src/core/errors.ts";
import { AsyncResult, ok } from "../../src/core/result.ts";
import {
  applicationToEmployee,
  bookingToEngagement,
  conversationToWorkItem,
  createFlows,
  quoteToOrder,
} from "../../src/flows/index.ts";

function fakeRelations() {
  const links: { source: FlowRef; target: FlowRef }[] = [];

  return {
    links,
    relations: {
      link: (source: FlowRef, target: FlowRef) => {
        links.push({ source, target });

        return AsyncResult.ok(true);
      },
      convertedInto: () => AsyncResult.ok(undefined),
    },
  };
}

const conversation = {
  id: "c1",
  subject: null,
  preview: "My invoice is wrong",
} as Conversation;

const event = (type: string, payload: unknown): FlowEvent => ({
  id: "e1",
  type,
  payload,
  tenant: "org-1",
});

describe("conversationToWorkItem", () => {
  it("creates a work item from the conversation, assigned like it", async () => {
    const { links, relations } = fakeRelations();
    const calls: unknown[] = [];

    const flows = createFlows({
      flows: [conversationToWorkItem()],
      clients: () => ({
        relations,
        inbox: { conversations: { get: () => AsyncResult.ok(conversation) } },
        workItems: {
          create: (
            tenant: string,
            input: unknown,
            assignees?: readonly string[],
          ) => {
            calls.push({ tenant, input, assignees });

            return AsyncResult.ok({ id: "w1" } as never);
          },
        },
      }),
    });

    const outcome = await flows.run(
      "conversationToWorkItem",
      event("inbox_conversation.opened", {
        conversationId: "c1",
        assigneeId: "u1",
      }),
    );

    expect(outcome).toEqual(
      ok({ status: "created", target: { type: "work_item", id: "w1" } }),
    );
    expect(calls).toEqual([
      {
        tenant: "org-1",
        input: { title: "My invoice is wrong", body: "My invoice is wrong" },
        assignees: ["u1"],
      },
    ]);
    expect(links).toEqual([
      {
        source: { type: "work_item", id: "w1" },
        target: { type: "inbox_conversation", id: "c1" },
      },
    ]);
  });

  it("takes a custom mapping, leaves it unassigned and reports a missing conversation", async () => {
    const { relations } = fakeRelations();
    const inputs: unknown[] = [];
    let found: Conversation | null = { ...conversation, preview: null };

    const clients = {
      relations,
      inbox: { conversations: { get: () => AsyncResult.ok(found) } },
      workItems: {
        create: (_: string, input: unknown, assignees?: readonly string[]) => {
          inputs.push({ input, assignees });

          return AsyncResult.ok({ id: "w2" } as never);
        },
      },
    };

    const defaults = createFlows({
      flows: [conversationToWorkItem({ assign: false })],
      clients: () => clients,
    });

    await defaults.run(
      "conversationToWorkItem",
      event("inbox_conversation.opened", {
        conversationId: "c1",
        assigneeId: "u1",
      }),
    );
    expect(inputs.at(-1)).toEqual({
      input: { title: "Conversation c1" },
      assignees: undefined,
    });

    const custom = createFlows({
      flows: [
        conversationToWorkItem({
          map: (c) => ({ title: `Support: ${c.id}`, priority: 2 }),
        }),
      ],
      clients: () => clients,
    });

    await custom.run(
      "conversationToWorkItem",
      event("inbox_conversation.opened", { conversationId: "c1" }),
    );
    expect(inputs.at(-1)).toEqual({
      input: { title: "Support: c1", priority: 2 },
      assignees: undefined,
    });

    found = null;

    const missing = await custom.run(
      "conversationToWorkItem",
      event("inbox_conversation.opened", { conversationId: "c1" }),
    );

    expect(!missing.ok && missing.error.kind).toBe("not_found");

    const failing = createFlows({
      flows: [conversationToWorkItem()],
      clients: () => ({
        ...clients,
        inbox: {
          conversations: {
            get: () => AsyncResult.err(dbError("network", "down")),
          },
        },
      }),
    });

    const down = await failing.run(
      "conversationToWorkItem",
      event("inbox_conversation.opened", { conversationId: "c1" }),
    );

    expect(!down.ok && down.error.kind).toBe("network");
  });
});

describe("applicationToEmployee", () => {
  it("calls fromApplication with the overrides and leaves the link to it", async () => {
    const { links, relations } = fakeRelations();
    const calls: unknown[] = [];

    const clients = {
      relations,
      employees: {
        fromApplication: (id: string, overrides?: unknown) => {
          calls.push({ id, overrides });

          return AsyncResult.ok({ id: "emp1" } as never);
        },
      },
    };

    const flows = createFlows({
      flows: [applicationToEmployee()],
      clients: () => clients,
    });

    const outcome = await flows.run(
      "applicationToEmployee",
      event("application.hired", {
        applicationId: "a1",
        organizationId: "org-1",
      }),
    );

    expect(outcome).toEqual(
      ok({ status: "created", target: { type: "employee", id: "emp1" } }),
    );
    expect(calls).toEqual([{ id: "a1", overrides: {} }]);
    expect(links).toEqual([]);

    const mapped = createFlows({
      flows: [
        applicationToEmployee({
          map: () => ({ employmentType: "contractor" }),
        }),
      ],
      clients: () => clients,
    });

    await mapped.run(
      "applicationToEmployee",
      event("application.hired", { applicationId: "a2" }),
    );
    expect(calls.at(-1)).toEqual({
      id: "a2",
      overrides: { employmentType: "contractor" },
    });
  });

  it("returns a failed conversion", async () => {
    const { relations } = fakeRelations();

    const flows = createFlows({
      flows: [applicationToEmployee()],
      clients: () => ({
        relations,
        employees: {
          fromApplication: () =>
            AsyncResult.err(
              dbError("raised", "not hired", {
                hint: "EMPLOYEE_APPLICATION_NOT_HIRED",
              }),
            ),
        },
      }),
    });

    const outcome = await flows.run(
      "applicationToEmployee",
      event("application.hired", { applicationId: "a1" }),
    );

    expect(!outcome.ok && outcome.error.kind).toBe("raised");
  });
});

describe("bookingToEngagement", () => {
  it("logs a meeting on the booking and the subjects the app adds", async () => {
    const { links, relations } = fakeRelations();
    const logs: unknown[] = [];

    const clients = {
      relations,
      engagements: {
        log: (tenant: string, input: unknown, subjects: readonly FlowRef[]) => {
          logs.push({ tenant, input, subjects });

          return AsyncResult.ok({ id: "g1" } as never);
        },
      },
    };

    const flows = createFlows({
      flows: [
        bookingToEngagement({
          subjects: () => [{ type: "customer", id: "cu1" }],
        }),
      ],
      clients: () => clients,
    });

    const outcome = await flows.run(
      "bookingToEngagement",
      event("booking.confirmed", { id: "b1", name: "Intro call" }),
    );

    expect(outcome).toEqual(
      ok({ status: "created", target: { type: "engagement", id: "g1" } }),
    );
    expect(logs).toEqual([
      {
        tenant: "org-1",
        input: {
          type: "meeting",
          title: "Intro call",
          externalRef: "booking:b1",
        },
        subjects: [
          { type: "booking", id: "b1" },
          { type: "customer", id: "cu1" },
        ],
      },
    ]);
    expect(links).toHaveLength(1);

    const custom = createFlows({
      flows: [
        bookingToEngagement({ map: () => ({ type: "call", title: "Call" }) }),
      ],
      clients: () => clients,
    });

    await custom.run(
      "bookingToEngagement",
      event("booking.confirmed", { id: "b2" }),
    );
    expect(logs.at(-1)).toMatchObject({
      input: { type: "call", title: "Call" },
      subjects: [{ type: "booking", id: "b2" }],
    });

    expect(
      await custom.run("bookingToEngagement", event("booking.confirmed", {})),
    ).toEqual(ok({ status: "skipped" }));

    const untitled = createFlows({
      flows: [bookingToEngagement()],
      clients: () => clients,
    });

    await untitled.run(
      "bookingToEngagement",
      event("booking.confirmed", { id: "b3" }),
    );
    expect(logs.at(-1)).toMatchObject({ input: { title: "Booking" } });
  });
});

describe("quoteToOrder", () => {
  it("runs the app's conversion on an accepted quote and links the order", async () => {
    const { links, relations } = fakeRelations();

    const flows = createFlows({
      flows: [
        quoteToOrder({
          create: ({ source }) => AsyncResult.ok({ id: `order-${source.id}` }),
        }),
      ],
      clients: () => ({ relations }),
    });

    expect(flows.matching("quote.accepted")).toEqual(["quoteToOrder"]);

    const outcome = await flows.run(
      "quoteToOrder",
      event("quote.accepted", { quoteId: "q1", organizationId: "org-1" }),
    );

    expect(outcome).toEqual(
      ok({ status: "created", target: { type: "order", id: "order-q1" } }),
    );
    expect(links).toEqual([
      {
        source: { type: "order", id: "order-q1" },
        target: { type: "quote", id: "q1" },
      },
    ]);
  });

  it("takes renamed subject types and another trigger", () => {
    const flow = quoteToOrder({
      on: "quote.signed",
      sourceType: "offer",
      targetType: "sales_order",
      create: () => AsyncResult.ok({ id: "x" }),
    });

    expect(flow.on).toBe("quote.signed");
    expect(flow.target).toBe("sales_order");
    expect(
      flow.source(event("quote.signed", { quoteId: "q1" }) as never),
    ).toEqual({ type: "offer", id: "q1" });
  });
});
