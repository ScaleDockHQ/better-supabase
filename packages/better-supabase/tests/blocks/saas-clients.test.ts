import { describe, expect, it } from "vitest";

import { createCustomFields } from "../../src/blocks/custom-fields/index.ts";
import { createImports } from "../../src/blocks/imports/index.ts";
import { suggestMapping } from "../../src/blocks/imports/index.ts";
import { createNumberSequences } from "../../src/blocks/number-sequences/index.ts";
import { createReminders } from "../../src/blocks/reminders/index.ts";
import { createShareLinks } from "../../src/blocks/share-links/index.ts";
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
      { id: "t1", name: "Ops", slug: "ops" },
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

  it("transitions a subject", async () => {
    const machine = createStateMachine(options({ transition: true }));
    expect(await machine.transition("quotes", "q1", "sent").orThrow()).toBe(
      true,
    );
    const denied = createStateMachine(options({ transition: false }));
    expect(
      await denied.transition("quotes", "q1", "sent", "nope").orThrow(),
    ).toBe(false);
  });

  it("saves and marks a reminder", async () => {
    const reminders = createReminders(
      options({
        save_reminder: { id: "r1" },
        mark_reminder_sent: true,
      }),
    );
    expect((await reminders.save("org", "invoices", "i1").orThrow()).id).toBe(
      "r1",
    );
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
      subjectType: "task",
      subjectId: "42",
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
    const tags = createTags(
      options({
        create_tag: { id: "g1", slug: "gold" },
        update_tag: true,
        delete_tag: true,
        tag: true,
        untag: false,
      }),
    );
    expect(
      (await tags.create("org", "deal", "Gold", "#fff", "hot").orThrow()).id,
    ).toBe("g1");
    expect(await tags.update("g1", "Gold").orThrow()).toBe(true);
    expect(await tags.delete("g1").orThrow()).toBe(true);
    expect(await tags.tag("org", "deals", "d1", "g1").orThrow()).toBe(true);
    expect(await tags.untag("org", "deals", "d1", "g1").orThrow()).toBe(false);
  });

  it("creates a share link, records a view and stores user state", async () => {
    const links = createShareLinks(
      options({
        create_share_link: { id: "s1", token: "once" },
        revoke_share_link: true,
        resolve_share_link: {
          id: "s1",
          subjectType: "files",
          subjectId: "f1",
          role: "edit",
          versionId: "v1",
        },
        record_view: true,
        list_share_links: [],
        set_user_state: true,
      }),
    );
    expect(
      (await links.create("org", "files", "f1", "edit").orThrow()).token,
    ).toBe("once");
    expect(await links.revoke("s1").orThrow()).toBe(true);
    expect(await links.resolve("once").orThrow()).toEqual({
      id: "s1",
      subjectType: "files",
      subjectId: "f1",
      role: "edit",
      versionId: "v1",
    });
    expect(
      (await links.create("org", "files", "f1", { versionId: "v1" }).orThrow())
        .id,
    ).toBe("s1");
    expect(
      await links.recordView("org", "files", "f1", "user", "u1").orThrow(),
    ).toBe(true);
    expect(await links.list("files", "f1").orThrow()).toEqual([]);
    expect(await links.setState("files", "f1", true).orThrow()).toBe(true);
  });

  it("saves a field definition and a value", async () => {
    const fields = createCustomFields(
      options({
        save_field_definition: { id: "d1" },
        delete_field_definition: true,
        read_field_values: [{ key: "tier" }],
        set_field_value: { id: "v1" },
      }),
    );
    expect(
      (
        await fields
          .saveDefinition("org", "employee", "tier", "Tier", "text", true)
          .orThrow()
      ).id,
    ).toBe("d1");
    expect(await fields.deleteDefinition("d1").orThrow()).toBe(true);
    expect(await fields.readValues("org", "employees", "e1").orThrow()).toEqual(
      [{ key: "tier" }],
    );
    expect(
      (await fields.setValue("org", "employees", "e1", "d1", "gold").orThrow())
        .id,
    ).toBe("v1");
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
    const tags = createTags(
      options({ create_tag: { id: "g1", slug: "gold", rank: "V" } }),
    );
    expect((await tags.create("org", "deal", "Gold").orThrow()).rank).toBe("V");
  });
});
