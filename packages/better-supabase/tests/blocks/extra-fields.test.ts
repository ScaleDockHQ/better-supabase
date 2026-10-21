import * as v from "valibot";
import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";

import { createSignatures } from "../../src/blocks/forms/index.ts";
import { createWebhookInbox } from "../../src/blocks/jobs/index.ts";
import { createShareLinks } from "../../src/blocks/share-links/index.ts";
import { createSla } from "../../src/blocks/sla/index.ts";
import { createSso } from "../../src/blocks/sso/index.ts";
import { createStateMachine } from "../../src/blocks/state-machine/index.ts";
import { createTags } from "../../src/blocks/tags/index.ts";
import { createTargets } from "../../src/blocks/targets/index.ts";
import { createTeams } from "../../src/blocks/teams/index.ts";
import { createTemplates } from "../../src/blocks/templates/index.ts";
import { createTimeTracking } from "../../src/blocks/time-tracking/index.ts";
import { createTrash } from "../../src/blocks/trash/index.ts";
import { createUndo } from "../../src/blocks/undo/index.ts";
import { createUsage } from "../../src/blocks/usage/index.ts";
import { createVersions } from "../../src/blocks/versions/index.ts";
import { createWaitlist } from "../../src/blocks/waitlist/index.ts";
import { createWebhooks } from "../../src/blocks/webhooks/index.ts";
import { createWorkItems } from "../../src/blocks/work-items/index.ts";
import { createWorkflowBuilder } from "../../src/blocks/workflow-builder/index.ts";
import { createWorkflows } from "../../src/blocks/workflows/index.ts";
import { dbError } from "../../src/core/errors.ts";

interface Call {
  readonly fn: string;
  readonly args: Readonly<Record<string, unknown>>;
}

/** A transport that answers each function from `results` and records the calls. */
function transport(results: Readonly<Record<string, unknown>> = {}): {
  readonly transport: BlockTransport;
  readonly calls: Call[];
} {
  const calls: Call[] = [];

  return {
    calls,
    transport: {
      call: (_schema, fn, args) => {
        calls.push({ fn, args });

        return Promise.resolve(results[fn] ?? null);
      },
    },
  };
}

const Fields = v.object({
  priority: v.picklist(["low", "high"]),
  points: v.pipe(
    v.union([v.number(), v.string()]),
    v.transform(Number),
    v.integer(),
  ),
});

const at = "2026-10-16T00:00:00Z";

describe("block fields", () => {
  it("tags: validates the fields of a create and parses them back", async () => {
    const fake = transport({
      create_tag: {
        id: "t1",
        slug: "urgent",
        rank: "V",
        fields: { priority: "high", points: "3" },
      },
    });

    const tags = createTags({ transport: fake.transport, fields: Fields });

    const tag = await tags
      .create("o", "label", "Urgent", undefined, undefined, {
        priority: "high",
        points: 3,
      })
      .orThrow();

    expect(tag.fields).toEqual({ priority: "high", points: 3 });
    expect(fake.calls[0]?.args["fields"]).toEqual({
      priority: "high",
      points: 3,
    });

    const refused = await tags.update("t1", null, {
      priority: "urgent" as "low",
    });

    expect(refused).toMatchObject({ ok: false, error: { kind: "validation" } });
    expect(fake.calls).toHaveLength(1);
  });

  it("leaves fields out of the call when there are none", async () => {
    const fake = transport({ update_team: { id: "t1", slug: "ops" } });

    const team = await createTeams({ transport: fake.transport })
      .update("t1", "Ops")
      .orThrow();

    expect(team).toEqual({ id: "t1", name: "Ops", slug: "ops", fields: {} });
    expect(fake.calls[0]?.args["fields"]).toBeUndefined();
  });

  it("parses the fields of every row a list returns", async () => {
    const fake = transport({
      list_teams: [
        {
          id: "t1",
          name: "A",
          slug: "a",
          fields: { priority: "low", points: 1 },
        },
        {
          id: "t2",
          name: "B",
          slug: "b",
          fields: { priority: "nope", points: 1 },
        },
      ],
      list_trash: [
        {
          id: "i1",
          batchId: "b1",
          count: 1,
          subjectType: "deal",
          subjectId: "d1",
          trashedAt: at,
          fields: { priority: "low", points: "2" },
        },
      ],
    });

    const teams = createTeams({ transport: fake.transport, fields: Fields });
    expect(await teams.list("o")).toMatchObject({
      ok: false,
      error: { kind: "validation" },
    });
    const trash = createTrash({ transport: fake.transport, fields: Fields });
    const [item] = await trash.list("o").orThrow();
    expect(item?.fields).toEqual({ priority: "low", points: 2 });
  });

  it("puts fields in attrs for the blocks that save from attrs", async () => {
    const fake = transport({
      save_sla_policy: {
        id: "p1",
        subject_type: "ticket",
        name: "Urgent",
        warn_at_percent: 80,
        business_hours: false,
        fields: { priority: "high", points: 1 },
      },
      save_target: {
        id: "g1",
        name: "Q4",
        metric: "deals.won_count",
        period_start: "2026-10-01",
        period_end: "2026-12-31",
        goal: "10",
      },
      create_work_item: {
        id: "w1",
        tenant_id: "o",
        number: "1",
        identifier: "TASK-1",
        title: "A",
        state: "backlog",
        rank: "V",
        created_at: at,
        updated_at: at,
        priority_label: "x",
      },
    });

    const policy = await createSla({
      transport: fake.transport,
      fields: Fields,
    })
      .savePolicy("o", {
        subjectType: "ticket",
        name: "Urgent",
        fields: { priority: "high", points: 1 },
      })
      .orThrow();

    expect(policy.fields.priority).toBe("high");
    expect(fake.calls[0]?.args["attrs"]).toMatchObject({
      fields: { priority: "high", points: 1 },
    });
    await createTargets({ transport: fake.transport })
      .save("o", { name: "Q4", fields: { budget: 3 } })
      .orThrow();
    expect(fake.calls[1]?.args["attrs"]).toMatchObject({
      fields: { budget: 3 },
    });

    const item = await createWorkItems({ transport: fake.transport })
      .create("o", { title: "A", fields: { priority_label: "x" } })
      .orThrow();

    expect(item.fields).toEqual({ priority_label: "x" });
    expect(fake.calls[2]?.args["attrs"]).toMatchObject({
      title: "A",
      fields: { priority_label: "x" },
    });
  });

  it("validates a work item change to an extra column before the batch", async () => {
    const fake = transport();

    const items = createWorkItems({
      transport: fake.transport,
      fields: v.object({ size: v.picklist(["s", "m", "l"]) }),
    });

    expect(
      await items.update([
        { workItemId: "w1", field: "title", value: "B" },
        { workItemId: "w1", field: "size", value: "xl" },
      ]),
    ).toMatchObject({ ok: false, error: { kind: "validation" } });
    expect(fake.calls).toHaveLength(0);
  });

  it("passes fields on the other writes", async () => {
    const entry = {
      id: "e1",
      organizationId: "o",
      userId: "u",
      startedAt: at,
      billable: false,
      createdAt: at,
      updatedAt: at,
      fields: { priority: "low", points: 1 },
    };

    const fake = transport({
      create_share_link: {
        id: "l1",
        token: "x",
        fields: { priority: "low", points: 1 },
      },
      start_timer: entry,
      update_time_entry: entry,
      snapshot_version: { id: "v1", number: 1, contentHash: "h" },
      join_waitlist: { position: 1, status: "waiting" },
      create_signature_request: {
        id: "r1",
        organizationId: "o",
        subjectType: "deal",
        subjectId: "d1",
        versionId: "v1",
        contentHash: "h",
        signers: ["u"],
        order: "parallel",
        status: "pending",
        createdAt: at,
        fields: { priority: "high", points: 2 },
      },
      save_workflow_definition: {
        id: "d1",
        slug: "s",
        name: "S",
        createdAt: at,
        updatedAt: at,
        fields: { priority: "low", points: 1 },
      },
      save_template: {
        id: "t1",
        scope: "tenant",
        type: "invoice",
        name: "T",
        language: "en",
        createdAt: at,
        updatedAt: at,
        fields: { priority: "low", points: 1 },
      },
    });

    const value = { priority: "low", points: 1 } as const;

    const link = await createShareLinks({
      transport: fake.transport,
      fields: Fields,
    })
      .create("o", "deal", "d1", { fields: value })
      .orThrow();

    expect(link.fields).toEqual(value);

    const time = createTimeTracking({
      transport: fake.transport,
      fields: Fields,
    });

    await time.start("o", { fields: value }).orThrow();
    await time.update("e1", { note: "n", fields: value }).orThrow();
    await createVersions({ transport: fake.transport, fields: Fields })
      .snapshot({
        organizationId: "o",
        subjectType: "deal",
        subjectId: "d1",
        fields: value,
      })
      .orThrow();
    await createWaitlist({ transport: fake.transport, fields: Fields })
      .join("a@b.c", { fields: value })
      .orThrow();

    const request = await createSignatures({
      transport: fake.transport,
      fields: Fields,
    })
      .request({
        organizationId: "o",
        subjectType: "deal",
        subjectId: "d1",
        signers: ["u"],
        fields: { priority: "high", points: 2 },
      })
      .orThrow();

    expect(request.fields.points).toBe(2);

    const definition = await createWorkflowBuilder({
      transport: fake.transport,
      fields: Fields,
    })
      .definitions.save({ slug: "s", name: "S", fields: value })
      .orThrow();

    expect(definition.fields).toEqual(value);

    const template = await createTemplates({
      transport: fake.transport,
      fields: Fields,
    })
      .save({ organizationId: "o", type: "invoice", name: "T", fields: value })
      .orThrow();

    expect(template.fields).toEqual(value);

    const sent = Object.fromEntries(
      fake.calls.map((call) => [
        call.fn,
        call.args["fields"] ??
          (call.args["patch"] as { fields?: unknown } | undefined)?.fields,
      ]),
    );

    for (const fn of [
      "create_share_link",
      "start_timer",
      "update_time_entry",
      "snapshot_version",
      "join_waitlist",
      "save_workflow_definition",
      "save_template",
    ]) {
      expect(sent[fn]).toEqual(value);
    }
  });

  it("stores a webhook with its fields and hands them to the handler", async () => {
    const fake = transport({
      receive_webhook: { id: 1, duplicate: false },
      claim_webhooks: [
        {
          id: 1,
          source: "crm",
          message_id: "m1",
          event_type: null,
          payload: {},
          headers: {},
          attempts: 1,
          received_at: at,
          fields: { priority: "high", points: "4" },
        },
      ],
      extend_webhook: 300,
      complete_webhook: true,
    });

    let claimed = 0;

    const inbox = createWebhookInbox({
      transport: {
        call: (schema, fn, args) =>
          fn === "claim_webhooks" && (claimed += 1) > 1
            ? Promise.resolve([])
            : fake.transport.call(schema, fn, args),
      },
      source: "crm",
      fields: Fields,
    });

    await inbox
      .store({ id: "m1", payload: {}, fields: { priority: "high", points: 4 } })
      .orThrow();
    expect(fake.calls[0]?.args["fields"]).toEqual({
      priority: "high",
      points: 4,
    });
    const seen: unknown[] = [];
    expect(
      await inbox.process((message) => {
        seen.push(message.fields);
      }),
    ).toEqual({ succeeded: 1, failed: 0 });
    expect(seen).toEqual([{ priority: "high", points: 4 }]);
  });
});

describe("block hooks", () => {
  it("refuses a call before it reaches the database", async () => {
    const fake = transport();
    const refusal = dbError("forbidden", "Not today");

    const clients = [
      createTags({
        transport: fake.transport,
        hooks: { delete: { before: () => refusal } },
      }).delete("t1"),
      createTeams({
        transport: fake.transport,
        hooks: { archive: { before: () => refusal } },
      }).archive("t1"),
      createShareLinks({
        transport: fake.transport,
        hooks: { revoke: { before: () => refusal } },
      }).revoke("l1"),
      createSso({
        transport: fake.transport,
        hooks: { removeDomain: { before: () => refusal } },
      }).removeDomain("d1"),
      createStateMachine({
        transport: fake.transport,
        hooks: { resume: { before: () => refusal } },
      }).resume("deal", "d1"),
      createUndo({
        transport: fake.transport,
        hooks: { apply: { before: () => refusal } },
      }).apply({}),
      createUsage({
        transport: fake.transport,
        hooks: { record: { before: () => refusal } },
      }).record("o", "api"),
      createWaitlist({
        transport: fake.transport,
        hooks: { reject: { before: () => refusal } },
      }).reject("e1"),
      createWebhooks({
        transport: fake.transport,
        hooks: { redeliver: { before: () => refusal } },
      }).redeliver("d1"),
      createWorkflows({
        transport: fake.transport,
        hooks: { schedules: { remove: { before: () => refusal } } },
      }).schedules.remove("s1"),
      createWorkflowBuilder({
        transport: fake.transport,
        hooks: { alerts: { remove: { before: () => refusal } } },
      }).alerts.remove("a1"),
      createWorkflowBuilder({
        transport: fake.transport,
        hooks: { run: { before: () => refusal } },
      }).run({ definition: "d1" }),
      createWebhookInbox({
        transport: fake.transport,
        source: "crm",
        hooks: { list: { before: () => refusal } },
      }).list({ tenant: "o" }),
    ];

    for (const result of await Promise.all(clients)) {
      expect(result).toMatchObject({ ok: false, error: { kind: "forbidden" } });
    }

    expect(fake.calls).toEqual([]);
  });
});
