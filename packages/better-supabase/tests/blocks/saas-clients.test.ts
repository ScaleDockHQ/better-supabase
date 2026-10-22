import { describe, expect, it } from "vitest";

import { createCustomFields } from "../../src/blocks/custom-fields/index.ts";
import {
  createImports,
  suggestMapping,
} from "../../src/blocks/imports/index.ts";
import { createNumberSequences } from "../../src/blocks/number-sequences/index.ts";
import { createReminders } from "../../src/blocks/reminders/index.ts";
import { createStateMachine } from "../../src/blocks/state-machine/index.ts";
import { createTags } from "../../src/blocks/tags/index.ts";
import { createTeams } from "../../src/blocks/teams/index.ts";

function fakeTransport(results: Record<string, unknown>) {
  return {
    call(schema: string, fn: string) {
      expect(schema).toBe("app");
      const result = results[fn];

      return result instanceof Error
        ? Promise.reject(result)
        : Promise.resolve(result);
    },
  };
}

const DEAL = { type: "deals", id: "d1" };

const EMPLOYEE = { type: "employees", id: "e1" };

const options = (results: Record<string, unknown>) => ({
  transport: fakeTransport(results),
  schema: "app",
});

describe("saas block clients", () => {
  it("creates, updates and lists teams", async () => {
    const teams = createTeams(
      options({
        create_team: { id: "t1", slug: "ops" },
        update_team: { id: "t1" },
        archive_team: true,
        delete_team: false,
        add_team_member: true,
        remove_team_member: false,
        list_teams: [{ id: "t1", name: "Ops", slug: "ops" }],
      }),
    );

    expect((await teams.create("org", "Ops", "desk").orThrow()).slug).toBe(
      "ops",
    );
    expect((await teams.update("t1", "Ops").orThrow()).name).toBe("Ops");
    expect(await teams.archive("t1").orThrow()).toBe(true);
    expect(await teams.delete("t1").orThrow()).toBe(false);
    expect(await teams.addMember("t1", "u1").orThrow()).toBe(true);
    expect(await teams.removeMember("t1", "u1").orThrow()).toBe(false);
    expect(await teams.list("org").orThrow()).toEqual([
      { id: "t1", name: "Ops", slug: "ops", fields: {} },
    ]);
  });

  it("allocates a number from a bigint, a string, or rejects anything else", async () => {
    const numbers = createNumberSequences(options({ next_number: 7n }));
    expect(await numbers.next("org", "invoice").orThrow()).toBe("7");
    const text = createNumberSequences(options({ next_number: "8" }));
    expect(await text.next("org", "invoice", "2026-01-01").orThrow()).toBe("8");
    const broken = createNumberSequences(options({ next_number: {} }));
    const result = await broken.next("org", "invoice");
    expect(result.ok).toBe(false);
  });

  it("calls next_number with the SQL parameter names", async () => {
    const calls: unknown[] = [];

    const numbers = createNumberSequences({
      schema: "app",
      transport: {
        call(_schema: string, _fn: string, args: unknown) {
          calls.push(args);

          return Promise.resolve(1);
        },
      },
    });

    await numbers.next("org", "invoice", "2026-01-01").orThrow();
    expect(calls).toEqual([
      { at: "2026-01-01", p_entity: "invoice", tenant: "org" },
    ]);
  });

  it("previews the formatted next number with preview_number", async () => {
    const calls: unknown[] = [];

    const numbers = createNumberSequences({
      schema: "app",
      transport: {
        call(_schema: string, fn: string, args: unknown) {
          calls.push([fn, args]);

          return Promise.resolve(fn === "preview_number" ? "INV-0042" : 1);
        },
      },
    });

    expect(await numbers.preview("org", "invoice").orThrow()).toBe("INV-0042");
    await numbers.preview("org", "invoice", "2026-01-01").orThrow();
    expect(calls).toEqual([
      ["preview_number", { p_entity: "invoice", p_tenant: "org" }],
      [
        "preview_number",
        { p_at: "2026-01-01", p_entity: "invoice", p_tenant: "org" },
      ],
    ]);

    const broken = createNumberSequences(options({ preview_number: 7 }));
    expect((await broken.preview("org", "invoice")).ok).toBe(false);
  });

  it("transitions a subject", async () => {
    const machine = createStateMachine(options({ transition: true }));
    expect(
      await machine.transition({ type: "quotes", id: "q1" }, "sent").orThrow(),
    ).toBe(true);
    const denied = createStateMachine(options({ transition: false }));
    expect(
      await denied
        .transition({ type: "quotes", id: "q1" }, "sent", "nope")
        .orThrow(),
    ).toBe(false);
  });

  it("saves and marks a reminder", async () => {
    const reminders = createReminders({
      ...options({ save_reminder: { id: "r1" }, mark_reminder_sent: true }),
      tenant: "org",
    });

    expect(
      (await reminders.save({ type: "invoices", id: "i1" }).orThrow()).id,
    ).toBe("r1");
    expect(
      await reminders.markSent("r1", "2026-01-01T00:00:00Z").orThrow(),
    ).toBe(true);
  });

  it("delivers a reminder once and notifies on the first delivery", async () => {
    const notified: unknown[] = [];
    let first = true;

    const reminders = createReminders({
      transport: {
        call: () => {
          const sent = first;
          first = false;

          return Promise.resolve(sent);
        },
      },
      notifyDelivery: (delivery) => void notified.push(delivery),
    });

    const payload = {
      reminderId: "r1",
      occurrenceAt: "2026-01-01T00:00:00Z",
      organizationId: "org",
      subject: { type: "task", id: "42" },
    };

    await reminders.job(
      payload,
      undefined as never,
      new AbortController().signal,
    );
    expect(await reminders.deliver(payload).orThrow()).toBe(false);
    expect(notified).toEqual([payload]);
    await expect(
      Promise.resolve(
        reminders.job("nope", undefined as never, new AbortController().signal),
      ),
    ).rejects.toThrow("reminders.deliver needs an object payload");
  });

  it("fails the delivery when the notification fails", async () => {
    const reminders = createReminders({
      transport: { call: () => Promise.resolve(true) },
      notifyDelivery: () => ({
        ok: false,
        error: { kind: "forbidden", message: "no", status: 403 },
      }),
    });

    const result = await reminders.deliver({
      reminderId: "r1",
      occurrenceAt: "2026-01-01T00:00:00Z",
      organizationId: "org",
    });

    expect(result.ok).toBe(false);
  });

  it("starts an import and suggests a header mapping", async () => {
    const imports = createImports(options({ start_import: { id: "i1" } }));
    expect((await imports.start("org", "people").orThrow()).id).toBe("i1");
    expect(
      suggestMapping(["Full Name", "email"], ["full_name", "email"]),
    ).toEqual({ "Full Name": "full_name", email: "email" });
  });

  it("creates tags and applies them", async () => {
    const tags = createTags({
      ...options({
        create_tag: { id: "g1", slug: "gold" },
        update_tag: true,
        delete_tag: true,
        tag: true,
        untag: false,
        list_tags: [
          {
            id: "g1",
            kind: "deal",
            name: "Gold",
            slug: "gold",
            color: "#fff",
            description: null,
            rank: "V",
          },
        ],
        subject_tags: null,
      }),
      tenant: "org",
    });

    expect(
      (await tags.create("deal", "Gold", "#fff", "hot").orThrow()).id,
    ).toBe("g1");
    expect(await tags.update("g1", "Gold").orThrow()).toBe(true);
    expect(await tags.delete("g1").orThrow()).toBe(true);
    expect(await tags.tag(DEAL, "g1").orThrow()).toBe(true);
    expect(await tags.untag(DEAL, "g1").orThrow()).toBe(false);
    expect(await tags.list("deal").orThrow()).toEqual([
      {
        id: "g1",
        kind: "deal",
        name: "Gold",
        slug: "gold",
        color: "#fff",
        rank: "V",
        fields: {},
      },
    ]);
    expect(await tags.forSubject(DEAL).orThrow()).toEqual([]);
  });

  it("saves a field definition and a value", async () => {
    const fields = createCustomFields({
      ...options({
        save_field_definition: { id: "d1" },
        delete_field_definition: true,
        read_field_values: [{ key: "tier" }],
        set_field_value: { id: "v1" },
      }),
      tenant: "org",
    });

    expect(
      (
        await fields
          .saveDefinition("employee", "tier", "Tier", "text", true)
          .orThrow()
      ).id,
    ).toBe("d1");
    expect(await fields.deleteDefinition("d1").orThrow()).toBe(true);
    expect(await fields.readValues(EMPLOYEE).orThrow()).toEqual([
      { key: "tier" },
    ]);
    expect((await fields.setValue(EMPLOYEE, "d1", "gold").orThrow()).id).toBe(
      "v1",
    );
  });

  it("lists an entity's field definitions", async () => {
    const fields = createCustomFields({
      ...options({
        list_field_definitions: [
          {
            id: "d1",
            entity: "customer",
            key: "tier",
            label: "Tier",
            type: "option",
            required: false,
            sensitive: true,
            rank: "V",
          },
          {
            id: "d2",
            entity: "customer",
            key: "notes",
            label: "Notes",
            type: "text",
            required: true,
            sensitive: false,
            rank: null,
          },
        ],
      }),
      tenant: "org",
    });

    expect(await fields.listDefinitions("customer").orThrow()).toEqual([
      {
        id: "d1",
        entity: "customer",
        key: "tier",
        label: "Tier",
        type: "option",
        required: false,
        sensitive: true,
        encrypted: false,
        rank: "V",
      },
      {
        id: "d2",
        entity: "customer",
        key: "notes",
        label: "Notes",
        type: "text",
        required: true,
        sensitive: false,
        encrypted: false,
      },
    ]);
  });

  it("reorders tags and field definitions with a key between the neighbours", async () => {
    const calls: { fn: string; args: unknown }[] = [];

    const transport = {
      call(_schema: string, fn: string, args: unknown) {
        calls.push({ fn, args });

        return Promise.resolve(true);
      },
    };

    const tags = createTags({ transport });
    expect(
      await tags.reorder("g1", { previous: "V", next: "W" }).orThrow(),
    ).toBe("VV");
    const fields = createCustomFields({ transport });
    expect(await fields.reorderDefinition("d1", { next: "V" }).orThrow()).toBe(
      "F",
    );
    expect(calls).toEqual([
      { fn: "rank_tag", args: { tag_id: "g1", rank: "VV" } },
      { fn: "rank_field_definition", args: { definition: "d1", rank: "F" } },
    ]);

    const wrong = await tags.reorder("g1", { previous: "W", next: "V" });
    expect(wrong.ok ? null : wrong.error).toMatchObject({
      kind: "invalid_request",
      hint: "RANK_KEY_INVALID",
    });
    expect(calls).toHaveLength(2);
  });

  it("returns a tag's rank key when the database sends one", async () => {
    const tags = createTags({
      ...options({ create_tag: { id: "g1", slug: "gold", rank: "V" } }),
      tenant: "org",
    });

    expect((await tags.create("deal", "Gold").orThrow()).rank).toBe("V");
  });
});
