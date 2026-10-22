import * as v from "valibot";
import { describe, expect, expectTypeOf, it, vi } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";

import { createContacts } from "../../src/blocks/contacts/index.ts";
import { createNotifications } from "../../src/blocks/notifications/index.ts";
import { createNumbering } from "../../src/blocks/numbering/index.ts";
import {
  createOnboarding,
  defineChecklist,
} from "../../src/blocks/onboarding/index.ts";
import { createOrganizations } from "../../src/blocks/organizations/index.ts";
import { createOutbox } from "../../src/blocks/outbox/index.ts";
import { createPipelines } from "../../src/blocks/pipelines/index.ts";
import { createPromotions } from "../../src/blocks/promotions/index.ts";
import { createPush } from "../../src/blocks/push/index.ts";
import { createRateLimit } from "../../src/blocks/queue/index.ts";
import { createRank } from "../../src/blocks/rank/index.ts";
import { createRelations } from "../../src/blocks/relations/index.ts";
import { createReminders } from "../../src/blocks/reminders/index.ts";
import { createSavedViews } from "../../src/blocks/saved-views/index.ts";
import { createServiceAccounts } from "../../src/blocks/service-accounts/index.ts";
import {
  createSettings,
  defineSettings,
} from "../../src/blocks/settings/index.ts";
import { dbError } from "../../src/core/errors.ts";

/** A transport that answers each function and records the calls. */
function fake(
  answers: Record<string, (args: Record<string, unknown>) => unknown>,
) {
  const call = vi.fn(
    async (_schema: string, fn: string, args: Record<string, unknown>) => {
      const answer = answers[fn];

      if (!answer) {
        throw new Error(`unexpected ${fn}`);
      }

      return answer(args);
    },
  );

  const transport: BlockTransport = { call };

  return { call, transport };
}

const refuse = () => dbError("forbidden", "refused by a hook");

const region = v.object({ region: v.picklist(["eu", "us"]) });

describe("block hooks", () => {
  it("refuse calls before they reach the database", async () => {
    const { call, transport } = fake({});

    const checklist = defineChecklist({
      id: "team",
      scope: "user",
      steps: [{ id: "invite" }],
    });

    const refused = [
      createRank({ transport, hooks: { move: { before: refuse } } }).move(
        "task",
        "t1",
        {},
      ),
      createRateLimit({
        transport,
        hooks: { check: { before: refuse } },
      }).check("api", "k"),
      createNumbering({ transport, hooks: { next: { before: refuse } } }).next(
        "o",
        "invoice",
      ),
      createPush({
        transport,
        hooks: { register: { before: refuse } },
      }).register({ token: "t", platform: "ios" }),
      createRelations({
        transport,
        tenant: "o",
        hooks: { unlink: { before: refuse } },
      }).unlink(
        { type: "task", id: "a" },
        { type: "task", id: "b" },
        { kind: "blocks" },
      ),
      createReminders({
        transport,
        tenant: "o",
        hooks: { save: { before: refuse } },
      }).save({ type: "task", id: "t1" }),
      createSavedViews({
        transport,
        hooks: { delete: { before: refuse } },
      }).delete("v1"),
      createServiceAccounts({
        transport,
        admin: { createUser: vi.fn(), deleteUser: vi.fn() },
        hooks: { list: { before: refuse } },
      }).list("o"),
      createOnboarding({
        transport,
        hooks: { complete: { before: refuse } },
      }).complete(checklist, "invite"),
      createSettings({
        transport,
        settings: defineSettings({
          user: { theme: { schema: v.string(), default: "light" } },
        }),
        hooks: { setUser: { before: refuse } },
      }).setUser("theme", "dark"),
      createOutbox({
        transport,
        source: "https://app.example.test",
        hooks: { emit: { before: refuse } },
      }).emit("invoice.paid"),
    ];

    for (const result of await Promise.all(refused)) {
      expect(result).toMatchObject({ ok: false, error: { kind: "forbidden" } });
    }

    expect(call).not.toHaveBeenCalled();
  });

  it("run around the calls a job handler makes", async () => {
    const { transport } = fake({
      rebalance_ranks: () => 3,
      purge_rate_limits: () => 2,
      mark_reminder_sent: () => false,
    });

    const rebalance = vi.fn();
    await createRank({
      transport,
      hooks: { rebalance: { after: rebalance } },
    }).job(
      { subjectType: "task", tenant: "o", group: null },
      undefined as never,
      new AbortController().signal,
    );
    expect(rebalance).toHaveBeenCalledOnce();
    const purge = vi.fn();
    await createRateLimit({
      transport,
      hooks: { purge: { after: purge } },
    }).purgeJob()({}, undefined as never, new AbortController().signal);
    expect(purge).toHaveBeenCalledOnce();
    const markSent = vi.fn();
    await createReminders({
      transport,
      notifyDelivery: () => undefined,
      hooks: { markSent: { after: markSent } },
    }).job(
      {
        reminderId: "r1",
        occurrenceAt: "2026-10-16T09:00:00Z",
        organizationId: "o",
      },
      undefined as never,
      new AbortController().signal,
    );
    expect(markSent).toHaveBeenCalledOnce();
  });
});

describe("block fields", () => {
  it("parses and validates service principal fields", async () => {
    const { transport } = fake({
      service_principals_list: () => [
        {
          id: "sp1",
          name: "Bot",
          role: "member",
          isDefault: false,
          createdBy: null,
          createdAt: "2026-10-16T09:00:00Z",
          disabledAt: null,
          fields: { region: "eu" },
        },
      ],
    });

    const createUser = vi.fn();

    const principals = createServiceAccounts({
      transport,
      admin: { createUser, deleteUser: vi.fn() },
      fields: region,
    });

    const [principal] = await principals.list("o").orThrow();
    expectTypeOf(principal?.fields.region).toEqualTypeOf<
      "eu" | "us" | undefined
    >();
    expect(principal?.fields).toEqual({ region: "eu" });

    const bad = await principals.create("o", "Bot", "member", {
      // @ts-expect-error not one of the regions
      fields: { region: "apac" },
    });

    expect(bad).toMatchObject({ ok: false, error: { kind: "validation" } });
    expect(createUser).not.toHaveBeenCalled();
  });

  it("writes relation fields on link and parses them on reads", async () => {
    const { call, transport } = fake({
      link: () => ({
        id: "r1",
        kind: "blocks",
        created: true,
        sourceType: "task",
        sourceId: "a",
        targetType: "task",
        targetId: "b",
        fields: { region: "us" },
      }),
      relations_of: () => [
        {
          id: "r1",
          kind: "blocks",
          direction: "out",
          type: "task",
          subjectId: "b",
          data: {},
          createdAt: "2026-10-16T09:00:00Z",
          fields: { region: "us" },
        },
      ],
    });

    const relations = createRelations({
      transport,
      tenant: "o",
      fields: region,
    });

    const linked = await relations
      .link(
        { type: "task", id: "a" },
        { type: "task", id: "b" },
        { kind: "blocks", fields: { region: "us" } },
      )
      .orThrow();

    expect(call.mock.calls[0]?.[2]).toMatchObject({ fields: { region: "us" } });
    expect(linked.fields).toEqual({ region: "us" });

    const [relation] = await relations.of({ type: "task", id: "a" }).orThrow();

    expect(relation?.fields.region).toBe("us");
  });

  it("writes reminder and saved view fields and reads them back", async () => {
    const { call, transport } = fake({
      save_reminder: () => ({ id: "r1", fields: { region: "eu" } }),
      save_view: () => ({ id: "v1", rank: "V", fields: { region: "eu" } }),
      list_views: () => [
        {
          id: "v1",
          list: "tasks",
          scope: "user",
          name: "Mine",
          kind: "table",
          state: {},
          rank: "V",
          isDefault: false,
          fields: { region: "us" },
        },
      ],
    });

    const reminders = createReminders({
      transport,
      tenant: "o",
      fields: region,
    });

    expect(
      await reminders
        .save({ type: "task", id: "t1" }, 15, { region: "eu" })
        .orThrow(),
    ).toEqual({ id: "r1", fields: { region: "eu" } });
    expect(call.mock.calls[0]?.[2]).toMatchObject({ fields: { region: "eu" } });
    const views = createSavedViews({ transport, fields: region });

    const saved = await views
      .save({
        organizationId: "o",
        list: "tasks",
        name: "Mine",
        state: {},
        fields: { region: "eu" },
      })
      .orThrow();

    expect(saved.fields).toEqual({ region: "eu" });
    const [view] = await views.list("o", "tasks").orThrow();
    expect(view?.fields.region).toBe("us");
  });

  it("writes promotion, pipeline and company fields and refuses bad ones", async () => {
    const { call, transport } = fake({
      save_promotion: () => ({ id: "p1", fields: { region: "eu" } }),
      list_pipelines: () => [
        {
          id: "pl1",
          tenant_id: "o",
          subject_type: "deal",
          key: "sales",
          name: "Sales",
          rank: "V",
          is_default: true,
          stages: [],
          fields: { region: "us" },
        },
      ],
      list_companies: () => [
        {
          id: "c1",
          tenant_id: "o",
          name: "Acme",
          lifecycle: "lead",
          archived_at: null,
          fields: { region: "eu" },
        },
      ],
    });

    const promotions = createPromotions({ transport, fields: region });

    const promotion = await promotions
      .savePromotion("o", {
        name: "Free shipping",
        discount: { kind: "free_shipping" },
        fields: { region: "eu" },
      })
      .orThrow();

    expect(promotion).toEqual({ id: "p1", fields: { region: "eu" } });
    expect(call.mock.calls[0]?.[2]).toMatchObject({ fields: { region: "eu" } });
    const pipelines = createPipelines({ transport, fields: region });
    const [pipeline] = await pipelines.list("o", "deal").orThrow();
    expect(pipeline?.fields.region).toBe("us");
    const parties = createContacts({ transport, fields: region });
    const page = await parties.listCompanies("o").orThrow();
    expect(page.items[0]?.fields.region).toBe("eu");

    const bad = await parties.saveCompany("o", {
      name: "Acme",
      // @ts-expect-error not one of the regions
      fields: { region: "apac" },
    });

    expect(bad).toMatchObject({ ok: false, error: { kind: "validation" } });
    expect(call).toHaveBeenCalledTimes(3);
  });

  it("sends notification fields and parses them on reads", async () => {
    const { call, transport } = fake({
      send_notification: () => ({ id: "n1", recipients: ["u1"] }),
      list_notifications: () => [
        {
          id: "r1",
          event_id: "n1",
          type: "task.assigned",
          data: { title: "Hi" },
          created_at: "2026-10-16T09:00:00Z",
          read_at: null,
          fields: { region: "us" },
        },
      ],
    });

    const notifications = createNotifications({
      transport,
      types: { "task.assigned": v.object({ title: v.string() }) },
      fields: region,
    });

    await notifications
      .send("task.assigned", {
        recipients: ["u1"],
        data: { title: "Hi" },
        fields: { region: "us" },
      })
      .orThrow();
    expect(call.mock.calls[0]?.[2]).toMatchObject({
      notification: { fields: { region: "us" } },
    });
    const [item] = await notifications.list().orThrow();
    expectTypeOf(item?.fields.region).toEqualTypeOf<"eu" | "us" | undefined>();
    expect(item?.fields).toEqual({ region: "us" });
  });

  it("checks invitation fields on invite and parses them on reads", async () => {
    const invitation = {
      id: "i1",
      tenant: "o",
      email: "a@example.test",
      role: "member",
      expires_at: "2026-10-23T09:00:00Z",
      organization: { id: "o" },
      prefill: {},
      inviter: null,
      fields: { region: "eu" },
    };

    const { call, transport } = fake({
      invite_member: () => ({ ...invitation, token: "tok" }),
      my_invitations: () => [invitation],
    });

    const organizations = createOrganizations({
      transport,
      invitationFields: region,
    });

    const bad = await organizations.invite({
      organizationId: "o",
      email: "a@example.test",
      role: "member",
      // @ts-expect-error not one of the regions
      fields: { region: "apac" },
    });

    expect(bad).toMatchObject({ ok: false, error: { kind: "validation" } });
    expect(call).not.toHaveBeenCalled();

    const sent = await organizations
      .invite({
        organizationId: "o",
        email: "a@example.test",
        role: "member",
        fields: { region: "eu" },
      })
      .orThrow();

    expect(call.mock.calls[0]?.[2]).toMatchObject({ fields: { region: "eu" } });
    expect(sent.invitation.fields).toEqual({ region: "eu" });
    expect(sent.invitation.extra).toEqual({});
    const [mine] = await organizations.myInvitations().orThrow();
    expect(mine?.fields.region).toBe("eu");
  });
});
