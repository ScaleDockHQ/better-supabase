import { describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { FlowClients, FlowEvent, FlowRef } from "../../src/flows/index.ts";

import { entitySchema } from "../../src/blocks/entity-schema.ts";
import { dbError } from "../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../src/core/result.ts";
import { createFlows, defineFlow } from "../../src/flows/index.ts";

interface Link {
  readonly source: FlowRef;
  readonly target: FlowRef;
}

function fakeRelations(failLink = false) {
  const links: Link[] = [];

  return {
    links,
    relations: {
      link: (source: FlowRef, target: FlowRef) => {
        if (failLink) {
          return AsyncResult.err(dbError("conflict", "link failed"));
        }

        links.push({ source, target });

        return AsyncResult.ok(true);
      },
      convertedInto: (origin: FlowRef, intoType: string) =>
        AsyncResult.ok(
          links.find(
            (link) =>
              link.target.type === origin.type &&
              link.target.id === origin.id &&
              link.source.type === intoType,
          )?.source.id,
        ),
    },
  };
}

interface Clients extends FlowClients {
  readonly notes: {
    create(title: string): PromiseLike<Result<{ readonly id: string }>>;
  };
}

function setup(options: { failLink?: boolean; failCreate?: boolean } = {}) {
  const { links, relations } = fakeRelations(options.failLink);
  const created: string[] = [];
  const tenants: string[] = [];

  const clients: Clients = {
    relations,
    notes: {
      create: (title) => {
        if (options.failCreate) {
          return AsyncResult.err(dbError("check", "no notes today"));
        }

        created.push(title);

        return AsyncResult.ok({ id: `note-${created.length}` });
      },
    },
  };

  const noteFromTicket = defineFlow<
    Clients,
    { readonly ticketId?: string; readonly organizationId?: string },
    { readonly title: string },
    { title: string }
  >({
    name: "noteFromTicket",
    on: ["ticket.opened", "ticket.reopened"],
    target: "note",
    source: (event) =>
      event.payload.ticketId === undefined
        ? undefined
        : { type: "ticket", id: event.payload.ticketId },
    load: ({ source }) => AsyncResult.ok({ title: `Ticket ${source.id}` }),
    input: entitySchema<{ title: string }>({
      fields: { title: { kind: "string", minLength: 1 } },
    }),
    map: (loaded) => ({ title: loaded.title }),
    create: (input, { clients: c }) => c.notes.create(input.title),
  });

  return { links, created, tenants, clients, noteFromTicket };
}

const event = (
  id: string,
  payload: unknown,
  extra: Partial<FlowEvent> = {},
): FlowEvent => ({
  id,
  type: "ticket.opened",
  payload,
  tenant: "org-1",
  ...extra,
});

describe("defineFlow", () => {
  it("stamps apiVersion 1", () => {
    expect(setup().noteFromTicket.apiVersion).toBe(1);
  });
});

describe("createFlows", () => {
  it("creates the target once and links it created_from the source", async () => {
    const { links, created, tenants, clients, noteFromTicket } = setup();
    const outcomes: string[] = [];

    const flows = createFlows({
      flows: [noteFromTicket],
      clients: (tenant) => {
        tenants.push(tenant);

        return clients;
      },
      onOutcome: (_, __, outcome) => outcomes.push(outcome.status),
    });

    const first = await flows.run(
      "noteFromTicket",
      event("e1", { ticketId: "t1" }),
    );

    const second = await flows.run(
      "noteFromTicket",
      event("e2", { ticketId: "t1" }),
    );

    expect(first).toEqual(
      ok({ status: "created", target: { type: "note", id: "note-1" } }),
    );
    expect(second).toEqual(
      ok({ status: "exists", target: { type: "note", id: "note-1" } }),
    );
    expect(created).toEqual(["Ticket t1"]);
    expect(links).toEqual([
      {
        source: { type: "note", id: "note-1" },
        target: { type: "ticket", id: "t1" },
      },
    ]);
    expect(tenants).toEqual(["org-1", "org-1"]);
    expect(outcomes).toEqual(["created", "exists"]);
  });

  it("skips an event without a source and reads the tenant from the payload", async () => {
    const { clients, noteFromTicket, tenants } = setup();

    const flows = createFlows({
      flows: [noteFromTicket],
      clients: (tenant) => {
        tenants.push(tenant);

        return clients;
      },
    });

    expect(await flows.run("noteFromTicket", event("e1", {}))).toEqual(
      ok({ status: "skipped" }),
    );

    const fromPayload = await flows.run(
      "noteFromTicket",
      event(
        "e2",
        { ticketId: "t2", organizationId: "org-2" },
        { tenant: null },
      ),
    );

    expect(fromPayload.ok).toBe(true);
    expect(tenants).toEqual(["org-2"]);
  });

  it("fails without a tenant, for an unknown flow and on duplicate names", async () => {
    const { clients, noteFromTicket } = setup();

    const flows = createFlows({
      flows: [noteFromTicket],
      clients: () => clients,
    });

    const missing = await flows.run(
      "noteFromTicket",
      event("e1", { ticketId: "t1" }, { tenant: "" }),
    );

    expect(!missing.ok && missing.error.hint).toBe("FLOW_TENANT_REQUIRED");

    const unknown = await flows.run("nope", event("e1", {}));
    expect(!unknown.ok && unknown.error.hint).toBe("FLOW_NOT_FOUND");

    expect(() =>
      createFlows({
        flows: [noteFromTicket, noteFromTicket],
        clients: () => clients,
      }),
    ).toThrow(TypeError);
  });

  it("stops on a failed load, validation, create or link", async () => {
    const base = setup();

    const failing = defineFlow({
      ...base.noteFromTicket,
      name: "failingLoad",
      load: () => AsyncResult.err(dbError("not_found", "gone")),
    });

    const invalid = defineFlow<
      Clients,
      { ticketId: string },
      undefined,
      { title: string }
    >({
      name: "invalid",
      on: "ticket.opened",
      target: "note",
      source: (e) => ({ type: "ticket", id: e.payload.ticketId }),
      input: entitySchema<{ title: string }>({
        fields: { title: { kind: "string", minLength: 1 } },
      }),
      map: () => ({ title: "" }),
      create: () => AsyncResult.ok({ id: "x" }),
    });

    const flows = createFlows({
      flows: [failing, invalid],
      clients: () => base.clients,
    });

    const loaded = await flows.run(
      "failingLoad",
      event("e1", { ticketId: "t1" }),
    );

    expect(!loaded.ok && loaded.error.kind).toBe("not_found");

    const validated = await flows.run(
      "invalid",
      event("e1", { ticketId: "t1" }),
    );

    expect(!validated.ok && validated.error.kind).toBe("validation");
    expect(
      !validated.ok &&
        validated.error.kind === "validation" &&
        validated.error.issues[0]?.path,
    ).toEqual(["title"]);

    const noCreate = setup({ failCreate: true });

    const createFails = createFlows({
      flows: [noCreate.noteFromTicket],
      clients: () => noCreate.clients,
    });

    const created = await createFails.run(
      "noteFromTicket",
      event("e1", { ticketId: "t1" }),
    );

    expect(!created.ok && created.error.kind).toBe("check");

    const noLink = setup({ failLink: true });

    const linkFails = createFlows({
      flows: [noLink.noteFromTicket],
      clients: () => noLink.clients,
    });

    const linked = await linkFails.run(
      "noteFromTicket",
      event("e1", { ticketId: "t1" }),
    );

    expect(!linked.ok && linked.error.kind).toBe("conflict");
  });

  it("returns a failed lineage read and skips the link for a flow that links itself", async () => {
    const base = setup();

    const broken: Clients = {
      ...base.clients,
      relations: {
        ...base.clients.relations,
        convertedInto: () => AsyncResult.err(dbError("network", "down")),
      },
    };

    const self = defineFlow<Clients, { ticketId: string }>({
      name: "self",
      on: "ticket.opened",
      target: "note",
      source: (e) => ({ type: "ticket", id: e.payload.ticketId }),
      map: () => undefined,
      create: () => AsyncResult.ok({ id: "n" }),
      linksItself: true,
    });

    const down = await createFlows({
      flows: [self],
      clients: () => broken,
    }).run("self", event("e1", { ticketId: "t1" }));

    expect(!down.ok && down.error.kind).toBe("network");

    const up = await createFlows({
      flows: [self],
      clients: () => base.clients,
    }).run("self", event("e1", { ticketId: "t1" }));

    expect(up).toEqual(
      ok({ status: "created", target: { type: "note", id: "n" } }),
    );
    expect(base.links).toEqual([]);
  });

  it("runs every matching flow from the sink and throws on a failure", async () => {
    const { clients, created, noteFromTicket } = setup();

    const flows = createFlows({
      flows: [noteFromTicket],
      clients: () => clients,
    });

    expect(flows.matching("ticket.reopened")).toEqual(["noteFromTicket"]);
    expect(flows.matching("other")).toEqual([]);

    await flows.sink()([
      event("e1", { ticketId: "t1" }),
      { ...event("e2", { ticketId: "t2" }), type: "other" },
    ]);
    expect(created).toEqual(["Ticket t1"]);

    const failing = setup({ failCreate: true });

    const sink = createFlows({
      flows: [failing.noteFromTicket],
      clients: () => failing.clients,
    }).sink();

    await expect(sink([event("e1", { ticketId: "t1" })])).rejects.toThrow(
      "no notes today",
    );
  });

  it("queues runs with a dedupe key and runs them from the handler", async () => {
    const { clients, created, noteFromTicket } = setup();
    const queued: { job: unknown; key: string }[] = [];

    const flows = createFlows({
      flows: [noteFromTicket],
      clients: () => clients,
      enqueue: (job, key) => {
        queued.push({ job, key });

        return AsyncResult.ok({ id: 1, duplicate: false });
      },
    });

    await flows.sink()([
      {
        ...event("e1", { ticketId: "t1" }),
        source: "tickets",
        createdAt: "2026-10-22T00:00:00Z",
      } as FlowEvent,
    ]);

    expect(queued).toEqual([
      {
        key: "flow:noteFromTicket:e1",
        job: {
          flow: "noteFromTicket",
          event: {
            id: "e1",
            type: "ticket.opened",
            payload: { ticketId: "t1" },
            subject: null,
            tenant: "org-1",
            actorId: null,
          },
        },
      },
    ]);
    expect(created).toEqual([]);

    await flows.handler()({
      flow: "noteFromTicket",
      event: event("e1", { ticketId: "t1" }),
    });
    expect(created).toEqual(["Ticket t1"]);

    const refusing = createFlows({
      flows: [noteFromTicket],
      clients: () => clients,
      enqueue: () => Promise.resolve(err(dbError("network", "queue down"))),
    });

    await expect(
      refusing.sink()([event("e2", { ticketId: "t2" })]),
    ).rejects.toThrow("queue down");
  });
});
