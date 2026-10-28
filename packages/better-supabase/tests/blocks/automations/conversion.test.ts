import type { StandardSchemaV1 } from "@standard-schema/spec";

import { describe, expect, it, vi } from "vitest";

import type {
  ConversionClients,
  ConversionRef,
} from "../../../src/blocks/automations/conversion.ts";
import type { Conversation } from "../../../src/blocks/inbox/types.ts";
import type { ActionCall } from "../../../src/core/automation.ts";
import type { Result } from "../../../src/core/result.ts";

import { defineConversionAction } from "../../../src/blocks/automations/conversion.ts";
import { employeeFromApplicationAction } from "../../../src/blocks/employees/actions.ts";
import { orderFromQuoteAction } from "../../../src/blocks/orders/actions.ts";
import { taskFromConversationAction } from "../../../src/blocks/tasks/actions.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult, err, ok } from "../../../src/core/result.ts";

function call(overrides: Partial<ActionCall> = {}): ActionCall {
  return {
    action: { kind: "convert" },
    origin: { type: "automation", id: "r1", name: "Convert" },
    context: { organizationId: "org", subjectType: "thing", subjectId: "t1" },
    key: "rule:r1:convert:e1",
    ...overrides,
  };
}

function relations(existing: Result<string | undefined> = ok(undefined)) {
  const link = vi.fn<
    (
      source: ConversionRef,
      target: ConversionRef,
      input: { readonly kind: "created_from" },
    ) => Promise<Result<unknown>>
  >(async () => ok(null));

  const convertedInto = vi.fn(async () => existing);

  return { link, convertedInto };
}

function schema<T>(
  check: (value: unknown) => StandardSchemaV1.Result<T>,
): StandardSchemaV1<T> {
  return { "~standard": { version: 1, vendor: "test", validate: check } };
}

describe("defineConversionAction", () => {
  it("creates the target and links it created_from the source", async () => {
    const rel = relations();

    const action = defineConversionAction<ConversionClients>({
      kind: "convert",
      title: "Convert",
      description: "Converts",
      targetType: "widget",
      clients: () => ({ relations: rel }),
      map: () => ({ name: "w" }),
      create: async () => ok({ id: "w1" }),
    });

    expect(action.description).toBe("Converts");
    expect(await action.run(call())).toEqual(
      ok({ status: "created", target: { type: "widget", id: "w1" } }),
    );
    expect(rel.link).toHaveBeenCalledWith(
      { type: "widget", id: "w1" },
      { type: "thing", id: "t1" },
      { kind: "created_from" },
    );
  });

  it("uses the renamed target type from the automation's config", async () => {
    const rel = relations(ok("x1"));

    const action = defineConversionAction<ConversionClients>({
      kind: "convert",
      title: "Convert",
      targetType: "widget",
      clients: () => ({ relations: rel }),
      map: () => null,
      create: async () => ok({ id: "w1" }),
    });

    expect(
      await action.run(
        call({ action: { kind: "convert", config: { targetType: "gadget" } } }),
      ),
    ).toEqual(ok({ status: "exists", target: { type: "gadget", id: "x1" } }));
    expect(rel.convertedInto).toHaveBeenCalledWith(
      { type: "thing", id: "t1" },
      "gadget",
    );
  });

  it("skips a call without a source", async () => {
    const create = vi.fn(async () => ok({ id: "w1" }));

    const action = defineConversionAction<ConversionClients>({
      kind: "convert",
      title: "Convert",
      targetType: "widget",
      source: (context) =>
        context.payload?.["ref"] === undefined
          ? undefined
          : { type: "thing", id: String(context.payload["ref"]) },
      clients: () => ({ relations: relations() }),
      map: () => null,
      create,
    });

    expect(await action.run(call())).toEqual(ok({ status: "skipped" }));
    expect(
      await action.run(
        call({
          context: {
            organizationId: "org",
            subjectType: "thing",
            subjectId: "t1",
            payload: { ref: "" },
          },
        }),
      ),
    ).toEqual(ok({ status: "skipped" }));
    expect(create).not.toHaveBeenCalled();
  });

  it("returns the errors of each step", async () => {
    const failure = err(dbError("not_found", "gone"));

    const base = {
      kind: "convert",
      title: "Convert",
      targetType: "widget",
      map: () => null,
    };

    expect(
      await defineConversionAction<ConversionClients>({
        ...base,
        clients: () => ({ relations: relations(failure) }),
        create: async () => ok({ id: "w1" }),
      }).run(call()),
    ).toEqual(failure);
    expect(
      await defineConversionAction<ConversionClients, string>({
        ...base,
        clients: () => ({ relations: relations() }),
        load: async () => failure,
        create: async () => ok({ id: "w1" }),
      }).run(call()),
    ).toEqual(failure);
    expect(
      await defineConversionAction<ConversionClients>({
        ...base,
        clients: () => ({ relations: relations() }),
        create: async () => failure,
      }).run(call()),
    ).toEqual(failure);

    const rel = relations();
    rel.link.mockResolvedValueOnce(failure);

    expect(
      await defineConversionAction<ConversionClients>({
        ...base,
        clients: () => ({ relations: rel }),
        create: async () => ok({ id: "w1" }),
      }).run(call()),
    ).toEqual(failure);
  });

  it("rejects a mapped input the target schema refuses", async () => {
    const create = vi.fn(async () => ok({ id: "w1" }));

    const action = defineConversionAction<
      ConversionClients,
      undefined,
      { readonly name: string }
    >({
      kind: "convert",
      title: "Convert",
      targetType: "widget",
      clients: () => ({ relations: relations() }),
      input: schema(() => ({
        issues: [
          { message: "Required", path: [{ key: "name" }, 0] },
          { message: "Bad" },
        ],
      })),
      map: () => ({ name: "" }),
      create,
    });

    const result = await action.run(call());

    expect(result).toMatchObject({
      ok: false,
      error: {
        kind: "validation",
        issues: [
          { message: "Required", path: ["name", 0] },
          { message: "Bad" },
        ],
      },
    });
    expect(create).not.toHaveBeenCalled();
  });

  it("passes the schema's output to create and leaves the link to a block that records it", async () => {
    const rel = relations();
    const create = vi.fn(async () => ok({ id: "w1" }));

    const action = defineConversionAction<
      ConversionClients,
      undefined,
      { readonly name: string }
    >({
      kind: "convert",
      title: "Convert",
      targetType: "widget",
      clients: () => ({ relations: rel }),
      input: schema(() => ({ value: { name: "trimmed" } })),
      map: () => ({ name: " trimmed " }),
      create,
      linksItself: true,
    });

    expect(await action.run(call())).toMatchObject({ ok: true });
    expect(create).toHaveBeenCalledWith({ name: "trimmed" }, expect.anything());
    expect(rel.link).not.toHaveBeenCalled();
  });
});

function conversation(fields: Partial<Conversation>): Conversation {
  // SAFETY: the action reads only id, subject and preview.
  return {
    id: "c1",
    subject: null,
    preview: null,
    ...fields,
  } as unknown as Conversation;
}

describe("taskFromConversationAction", () => {
  function setup(found: Result<Conversation | null>, assign?: boolean) {
    const create = vi.fn(
      async (_tenant: string, input: { readonly title: string }) =>
        ok({ id: "task1", ...input }),
    );

    const action = taskFromConversationAction({
      ...(assign === undefined ? {} : { assign }),
      clients: () => ({
        relations: relations(),
        inbox: { conversations: { get: async () => found } },
        // SAFETY: the action reads only the created task's id.
        tasks: { create } as never,
      }),
    });

    return { action, create };
  }

  it("titles the task from the subject and assigns the conversation's assignee", async () => {
    const { action, create } = setup(
      ok(conversation({ subject: "Refund", preview: "Hello" })),
    );

    expect(
      await action.run(
        call({
          context: {
            organizationId: "org",
            subjectType: "inbox_conversation",
            subjectId: "c1",
            payload: { assigneeId: "u1" },
          },
        }),
      ),
    ).toMatchObject({ ok: true, data: { status: "created" } });
    expect(create).toHaveBeenCalledWith(
      "org",
      expect.objectContaining({ title: "Refund", body: "Hello" }),
      ["u1"],
    );
  });

  it("names an empty conversation by its id and doesn't assign when turned off", async () => {
    const { action, create } = setup(ok(conversation({})), false);

    await action.run(
      call({
        context: {
          organizationId: "org",
          subjectType: "inbox_conversation",
          subjectId: "c1",
          payload: { assigneeId: "u1" },
        },
      }),
    );

    expect(create).toHaveBeenCalledWith(
      "org",
      expect.objectContaining({ title: "Conversation c1" }),
      undefined,
    );
  });

  it("fails for a missing conversation", async () => {
    expect(await setup(ok(null)).action.run(call())).toMatchObject({
      ok: false,
      error: { kind: "not_found" },
    });

    const failure = err(dbError("not_found", "gone"));

    expect(await setup(failure).action.run(call())).toEqual(failure);
  });

  it("returns the tasks block's error", async () => {
    const failure = err(dbError("not_found", "gone"));

    const action = taskFromConversationAction({
      map: () => ({ title: "Mapped" }),
      clients: () => ({
        relations: relations(),
        inbox: { conversations: { get: async () => ok(conversation({})) } },
        tasks: { create: async () => failure },
      }),
    });

    expect(await action.run(call())).toEqual(failure);
  });
});

describe("employeeFromApplicationAction", () => {
  it("preboards through employees.fromApplication without its own link", async () => {
    const rel = relations();
    const fromApplication = vi.fn(async () => ok({ id: "e1" }));

    const action = employeeFromApplicationAction({
      map: () => ({ jobTitle: "Engineer" }),
      clients: () => ({
        relations: rel,
        // SAFETY: the action reads only the created employee's id.
        employees: { fromApplication } as never,
      }),
    });

    expect(await action.run(call())).toEqual(
      ok({ status: "created", target: { type: "employee", id: "e1" } }),
    );
    expect(fromApplication).toHaveBeenCalledWith("t1", {
      jobTitle: "Engineer",
    });
    expect(rel.link).not.toHaveBeenCalled();
  });

  it("returns the employees block's error", async () => {
    const failure = err(dbError("not_found", "gone"));

    const action = employeeFromApplicationAction({
      clients: () => ({
        relations: relations(),
        employees: { fromApplication: async () => failure },
      }),
    });

    expect(await action.run(call())).toEqual(failure);
  });
});

describe("orderFromQuoteAction", () => {
  it("creates the order the app supplies and links it", async () => {
    const rel = relations();

    const action = orderFromQuoteAction({
      clients: () => ({ relations: rel }),
      create: async () => ok({ id: "o1" }),
    });

    expect(await action.run(call())).toEqual(
      ok({ status: "created", target: { type: "order", id: "o1" } }),
    );
    expect(rel.link).toHaveBeenCalledOnce();
  });

  it("orders the quote through the orders client without a create", async () => {
    const rel = relations();

    const fromQuote = vi.fn(() =>
      AsyncResult.ok({ order: { id: "o2" }, created: true }),
    );

    const action = orderFromQuoteAction({
      clients: () => ({ relations: rel, orders: { fromQuote } }),
    });

    expect(await action.run(call())).toEqual(
      ok({ status: "created", target: { type: "order", id: "o2" } }),
    );
    expect(fromQuote).toHaveBeenCalledWith("t1");
  });

  it("fails without an orders client or a create", async () => {
    const action = orderFromQuoteAction({
      clients: () => ({ relations: relations() }),
    });

    const result = await action.run(call());

    expect(result).toMatchObject({
      ok: false,
      error: { hint: "ORDERS_CLIENT_MISSING" },
    });
  });
});
