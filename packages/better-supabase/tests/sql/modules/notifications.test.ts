import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import {
  customContracts,
  moduleBody,
  renderBlocks,
} from "../../../src/sql/render.ts";
import { callerOnlyProvider } from "../../fixtures/authorization-provider.ts";

const body = (modules: AnyBlocksConfig = {}) =>
  moduleBody("notifications", { modules })!;

const CENTRAKIT: AnyBlocksConfig = {
  notifications: {
    mode: "adopt",
    schema: "public",
    idType: "uuid",
    columns: {
      events: { actor: "actor_user_id", data: "metadata" },
      recipients: { user: "recipient_user_id" },
    },
    options: {
      topic: "organization:{tenantId}:notifications:{userId}",
      channels: ["in_app", "email"],
    },
  },
};

describe("notifications module", () => {
  it("broadcasts an update only when a read, dismissed or resolved time changes", () => {
    const sql = body();
    expect(sql).toContain(
      'create trigger "bsb_notification_broadcast" after insert on "better_supabase"."notification_recipients"',
    );
    expect(sql).toContain(
      'after update of "read_at", "dismissed_at", "resolved_at" on "better_supabase"."notification_recipients"\n  for each row when (old."read_at" is distinct from new."read_at" or old."dismissed_at" is distinct from new."dismissed_at" or old."resolved_at" is distinct from new."resolved_at")',
    );
    expect(sql).toContain("notification_recipients_unread_idx");
    expect(sql).toContain("notification_events_created_at_idx");
  });

  it("owns its tables with RLS and keeps notify for the definer", () => {
    const sql = body();
    expect(sql).toContain(
      'create table if not exists "better_supabase"."notification_events" (',
    );
    expect(sql).toContain('"data" jsonb not null default');
    expect(sql).toContain("notification_events_key_idx");
    expect(sql).toContain(
      'grant update ("read_at", "dismissed_at") on "better_supabase"."notification_recipients" to authenticated;',
    );
    expect(sql).toContain("notification_deliveries");
    expect(sql).toContain("notification_subscriptions");
    expect(sql).toContain("notification_preferences");
    expect(sql).toMatch(/function "better_supabase"\."notify"\(.*jsonb\)/);
    expect(sql).toContain("security definer");
    expect(sql).toContain("perform realtime.send(");
    expect(sql).toContain("'notifications:' || new.\"user_id\"::text");
  });

  it("adopts CentraKit's tables and its tenant topic", () => {
    const sql = body(CENTRAKIT);
    expect(sql).not.toContain("create table if not exists");
    expect(sql).toContain('"public"."notification_events"');
    expect(sql).toContain(
      `'organization:' || new."organization_id"::text || ':notifications:' || new."recipient_user_id"::text`,
    );
    expect(sql).toContain("'notification_created'");
    expect(sql).toContain("'notification_updated'");
  });

  it("drops the tables mapped to null and the columns it can live without", () => {
    const sql = body({
      notifications: {
        tables: { deliveries: null, subscriptions: null, preferences: null },
        columns: {
          events: { key: null, priority: null },
          recipients: { resolvedAt: null },
        },
        options: { realtime: "none" },
      },
    });

    expect(sql).not.toContain("notification_deliveries");
    expect(sql).not.toContain("notification_subscriptions");
    expect(sql).not.toContain('"idempotency_key"');
    expect(sql).not.toContain("realtime.send(");
    expect(sql).toContain("drop trigger if exists");
    expect(sql).toContain(
      `overlay(overlay(v_hash placing '8' from 13 for 1) placing to_hex(8 | (('x' || substr(v_hash, 17, 1))::bit(4)::integer & 3)) from 17 for 1)::uuid`,
    );
    expect(sql).toContain(`where ev."id" = v_hash::uuid;`);
    expect(sql).not.toMatch(/md5\([^;]*\)::uuid/);
  });

  it("adds the recipients table to the publication in changes mode", () => {
    expect(
      body({ notifications: { options: { realtime: "changes" } } }),
    ).toContain("alter publication supabase_realtime add table");
  });

  it("checks permissions and emits through the outbox when they are installed", () => {
    const plain = renderBlocks(["notifications"]).at(-1)!.contents;
    expect(plain).not.toContain("member_can");
    expect(plain).not.toContain("emit_event");
    const files = renderBlocks(["permissions", "outbox", "notifications"]);

    const sql = files.find((file) =>
      file.path.includes("notifications"),
    )!.contents;

    expect(sql).toContain("member_can");
    expect(sql).toMatch(
      /create policy [\s\S]*better_supabase\.tenant_ids_with\('notifications\.read'\)/,
    );
    expect(sql).not.toMatch(/create policy [^;]*member_can/);
    expect(sql).toContain("'notifications.send'");
    expect(sql).toContain("emit_event('notification.created'");
  });

  it("retries deliveries with backoff and gives up after max attempts", () => {
    const sql = body();
    expect(sql).toContain(
      '"next_attempt_at" timestamptz not null default now()',
    );
    expect(sql).toContain('and d."next_attempt_at" <= now()');
    expect(sql).toMatch(/v_status := 'failed'/);
    expect(sql).toContain("'The lease ran out on the last attempt'");
    expect(sql).toContain(
      'drop function if exists "better_supabase"."complete_notification_delivery"(uuid, text, text, text, text);',
    );

    const plain = body({
      notifications: {
        columns: { deliveries: { nextAttemptAt: null, attempts: null } },
      },
    });

    expect(plain).not.toContain("next_attempt_at");
    expect(plain).not.toContain("v_status := 'failed'");
  });

  it("resolves preferences in one query, caps recipients and pages by (created_at, id)", () => {
    const sql = body();
    expect(sql).toContain("select distinct on (x, c)");
    expect(sql).toContain("case c when 'in_app' then true else false end");
    expect(sql).toContain("NOTIFICATION_TOO_MANY_RECIPIENTS");
    expect(sql).toContain("> 1000 then");
    expect(sql).toContain("before_id uuid default null");
    expect(sql).toContain('function "better_supabase"."purge_notifications"');
    expect(
      body({
        notifications: {
          options: { channelDefaults: { email: true }, maxRecipients: 50 },
        },
      }),
    ).toContain(
      "case c when 'email' then true when 'in_app' then true else false end",
    );
    expect(() =>
      body({ notifications: { options: { maxRecipients: 0 } } }),
    ).toThrow(/maxRecipients/);
  });

  it("rejects options it would splice into SQL or can't honor", () => {
    expect(() =>
      body({ notifications: { options: { topic: "notifications" } } }),
    ).toThrow(/\{userId\}/);
    expect(() =>
      body({ notifications: { options: { topic: "n:{userId}'; drop" } } }),
    ).toThrow(/topic/);
    expect(() =>
      body({
        notifications: {
          options: { topic: "organization:{tenantId}:{userId}" },
          columns: { recipients: { tenant: null } },
        },
      }),
    ).toThrow(/no tenant column/);
    expect(() =>
      body({ notifications: { options: { realtime: "pusher" } } }),
    ).toThrow(/realtime/);
  });

  it("renders nothing in custom mode and lists the contract the app must provide", () => {
    const custom: AnyBlocksConfig = { notifications: { mode: "custom" } };
    expect(moduleBody("notifications", { modules: custom })).toBeUndefined();
    const [contract] = customContracts(["notifications"], { modules: custom });
    expect(contract!.functions.map((fn) => fn.name)).toEqual([
      "notify",
      "send_notification",
      "send_notifications",
      "get_notification",
      "notification_enabled",
      "list_notifications",
      "notification_page",
      "notification_counts",
      "mark_notifications_read",
      "mark_notifications_unread",
      "dismiss_notifications",
      "purge_notifications",
      "resolve_notifications",
      "set_notification_subscription",
      "list_notification_subscriptions",
      "set_notification_preference",
      "list_notification_preferences",
      "claim_notification_deliveries",
      "complete_notification_delivery",
    ]);

    const [minimal] = customContracts(["notifications"], {
      modules: {
        notifications: {
          mode: "custom",
          tables: { deliveries: null, subscriptions: null, preferences: null },
          columns: { recipients: { resolvedAt: null } },
        },
      },
    });

    expect(minimal!.functions).toHaveLength(12);
  });

  it("reads one notification and returns the changed ones from each update", () => {
    const sql = body();
    expect(sql).toContain(
      `create or replace function "better_supabase"."get_notification"(id uuid)`,
    );
    expect(sql).toContain(
      `where rc."id" = get_notification.id\n    and rc."user_id" = auth.uid()`,
    );
    expect(sql).toMatch(
      /function "better_supabase"\."send_notification"\(notification jsonb\)\nreturns jsonb/,
    );
    expect(sql).toContain(
      `return jsonb_build_object('id', v_event, 'recipients', to_jsonb(v_recipients));`,
    );
    expect(sql).toContain(
      `select ("better_supabase"."send_notification"(notification) ->> 'id')::uuid`,
    );

    for (const fn of [
      "mark_notifications_read",
      "mark_notifications_unread",
      "dismiss_notifications",
      "resolve_notifications",
    ]) {
      expect(sql).toMatch(
        new RegExp(
          `function "better_supabase"\\."${fn}"\\([^)]*\\)\\nreturns jsonb`,
        ),
      );
      expect(sql).toContain(
        `drop function if exists "better_supabase"."${fn}"(`,
      );
    }

    expect(sql).toContain(`filter (where rc."user_id" = auth.uid()), '[]')`);
    expect(sql).toContain(`rc."event_id" into v_changed;`);
  });

  it("pages, searches, filters by subject type and reads the caller's settings", () => {
    const sql = body();
    expect(sql).toContain(
      'create or replace function "better_supabase"."notification_page"(',
    );
    expect(sql).toContain("'total', (select count(*) from matched)");
    expect(sql).toContain(
      "offset greatest(coalesce(notification_page.skip, 0), 0)",
    );
    expect(sql).toContain(
      `case when coalesce(list_notifications.status, 'all') = 'settled' then (rc."resolved_at" is not null or rc."dismissed_at" is not null) when list_notifications.dismissed is null then true else (rc."dismissed_at" is not null) = list_notifications.dismissed end`,
    );
    expect(sql).toContain(
      `and (notification_page.read is null or (rc."read_at" is not null) = notification_page.read)`,
    );
    expect(sql).toContain(
      `and (notification_page.resolved is null or (rc."resolved_at" is not null) = notification_page.resolved)`,
    );
    expect(sql).toContain(
      `drop function if exists "better_supabase"."notification_page"(uuid, text, text[], text[], text, integer, integer);`,
    );
    expect(sql).toContain(
      `or ev."subject_type" = any(list_notifications.subject_types)`,
    );
    expect(sql).toContain(
      `concat_ws(' ', ev."summary", ev."subject_label", ev."type") ilike '%' || replace(replace(replace(btrim(list_notifications.search), chr(92), chr(92) || chr(92))`,
    );
    expect(sql).toContain(
      `drop function if exists "better_supabase"."list_notifications"(uuid, text, text[], timestamptz, integer, uuid);`,
    );
    expect(sql).toContain(
      `'actionable_subjects', count(distinct case when ev."subject_type" is not null and ev."subject_id" is not null then jsonb_build_array(ev."organization_id", ev."subject_type", ev."subject_id")::text else rc."id"::text end)`,
    );
    expect(sql).toContain(`set "read_at" = null`);

    for (const fn of [
      /mark_notifications_unread"?\(uuid\[\], uuid\) from public, anon;/,
      /list_notification_subscriptions"?\(uuid, text, text\) from public, anon;/,
      /list_notification_preferences"?\(uuid\) from public, anon;/,
    ]) {
      expect(sql).toMatch(fn);
    }

    const bare = body({
      notifications: {
        tables: { subscriptions: null, preferences: null },
        columns: {
          events: { subjectType: null, subjectId: null, summary: null },
          recipients: { resolvedAt: null },
        },
      },
    });

    expect(bare).not.toContain("list_notification_subscriptions");
    expect(bare).not.toContain("list_notification_preferences");
    expect(bare).toContain("(list_notifications.subject_types is null)");
    expect(bare).toContain(`'actionable_subjects', 0`);
    expect(bare).toContain(
      `then rc."dismissed_at" is not null when list_notifications.dismissed is null then true`,
    );
    expect(bare).toContain(
      "and (list_notifications.resolved is null or not list_notifications.resolved)",
    );
  });

  it("skips the recipient read filter when the provider answers for the caller only", () => {
    const notify = (modules: AnyBlocksConfig) =>
      renderBlocks(["permissions", "notifications"], {
        modules,
        accessProvider: callerOnlyProvider,
      }).find((file) => file.path.includes("notifications"))!.contents;

    expect(notify({})).toContain("better_supabase.member_can(x, v_tenant,");

    const callerOnly = notify({ permissions: { model: "provider" } });

    expect(callerOnly).not.toContain("better_supabase.member_can(x,");
    expect(callerOnly).toContain(
      "better_supabase.member_can(auth.uid(), v_tenant,",
    );
    expect(callerOnly).toContain(
      "-- The provider model answers for the caller only, so recipients are not",
    );
  });
});

describe("notification subjects", () => {
  it("deletes a subject's notifications and subscriptions when the subject row is deleted", () => {
    const sql = body({
      notifications: {
        options: {
          subjects: {
            "time-off-request": {
              table: "app.time_off_requests",
              cascade: true,
            },
            expense: { table: "expenses", tenant: false, cascade: true },
            invoice: { table: "invoices" },
          },
        },
      },
    });

    expect(sql).toContain(
      'create or replace function "better_supabase"."notifications_subject_deleted"()',
    );
    expect(sql).toContain(
      "v_tenant text := case when tg_nargs > 2 then to_jsonb(old) ->> tg_argv[2] end;",
    );
    expect(sql).toContain(
      `  if v_tenant is null then
    delete from "better_supabase"."notification_events" x where x."subject_type" = v_type and x."subject_id" = v_id;
    delete from "better_supabase"."notification_subscriptions" x where x."subject_type" = v_type and x."subject_id" = v_id;
  else
    delete from "better_supabase"."notification_events" x where x."organization_id" = v_tenant::uuid and x."subject_type" = v_type and x."subject_id" = v_id;
    delete from "better_supabase"."notification_subscriptions" x where x."organization_id" = v_tenant::uuid and x."subject_type" = v_type and x."subject_id" = v_id;
  end if;`,
    );
    expect(sql).toContain(
      `create trigger "bsb_notifications_time-off-request_cascade"
  after delete on "app"."time_off_requests"
  for each row execute function "better_supabase"."notifications_subject_deleted"('time-off-request', 'id', 'organization_id');`,
    );
    expect(sql).toContain(
      `after delete on "public"."expenses"
  for each row execute function "better_supabase"."notifications_subject_deleted"('expense', 'id');`,
    );
    expect(sql).not.toContain("bsb_notifications_invoice_cascade");
    expect(body()).not.toContain("notifications_subject_deleted");
  });

  it("leaves subscriptions alone without the table and needs the subject columns", () => {
    const subjects = { task: { table: "tasks", cascade: true } };

    const sql = body({
      notifications: { tables: { subscriptions: null }, options: { subjects } },
    });

    expect(sql).toContain("notifications_subject_deleted");
    expect(sql).not.toContain("notification_subscriptions");

    const untenanted = body({
      notifications: {
        columns: { events: { tenant: null }, subscriptions: { tenant: null } },
        options: { subjects },
      },
    });

    expect(untenanted).not.toContain("tg_argv[2]");
    expect(untenanted).toContain(
      `"notifications_subject_deleted"('task', 'id');`,
    );
    expect(untenanted).toContain(
      `delete from "better_supabase"."notification_events" x where x."subject_type" = v_type and x."subject_id" = v_id;`,
    );
    expect(() =>
      body({
        notifications: {
          columns: { events: { subjectType: null } },
          options: { subjects },
        },
      }),
    ).toThrow(/needs the subjectType and subjectId columns/);
    expect(() =>
      body({
        notifications: {
          options: { subjects: { "Time-Off": { table: "t", cascade: true } } },
        },
      }),
    ).toThrow(/lowercase letters, digits, hyphens and underscores/);
    expect(() =>
      body({
        notifications: {
          options: { subjects: { task: { table: "t", cascade: "yes" } } },
        },
      }),
    ).toThrow(/cascade must be true or false/);
  });
});

describe("notification actors", () => {
  it("reads actor profiles only next to the profiles module", () => {
    const file = (names: readonly string[]) =>
      renderBlocks(names).find(
        (entry) => entry.module === "notifications" && entry.kind === "schema",
      )!.contents;

    const sql = file(["notifications", "profiles"]);
    expect(sql).toContain(
      'create or replace function "better_supabase"."notification_actors"(ids uuid[])',
    );
    expect(sql).toContain("'username', pr.\"username\"");
    expect(sql).toContain("'avatarPath', pr.\"avatar_path\"");
    expect(
      renderBlocks(["notifications", "profiles"], {
        modules: {
          profiles: { mode: "adopt", tables: { profiles: "public.profiles" } },
        },
      }).find(
        (entry) => entry.module === "notifications" && entry.kind === "schema",
      )!.contents,
    ).not.toContain("avatarPath");
    expect(sql).toContain(
      'where rc."user_id" = auth.uid() and ev."actor_id" = pr."id"',
    );
    expect(file(["notifications"])).not.toContain("notification_actors");
  });

  it("adds watchers unless watchers is false and drops excluded users", () => {
    const sql = body({});
    expect(sql).toContain(
      "if coalesce((notification ->> 'watchers')::boolean, true) then",
    );
    expect(sql).toContain(
      "where not x = any (array(select e::uuid from jsonb_array_elements_text(notification -> 'exclude') e))",
    );
  });

  it("lets a sender add a level for another member only when none is set", () => {
    const sql = renderBlocks(["permissions", "notifications"])
      .filter((file) => file.module === "notifications")
      .map((file) => file.contents)
      .join("\n");

    expect(body({})).not.toContain("member_can(v_user");
    expect(sql).toContain(
      'set_notification_subscription"(subject_type text, subject_id text, level text, tenant uuid default null, member uuid default null, if_absent boolean default false)',
    );
    expect(sql).toContain(
      "and coalesce(better_supabase.member_can(auth.uid(), set_notification_subscription.tenant, 'notifications.send'), false)",
    );
    expect(sql).toContain(
      "if coalesce(set_notification_subscription.if_absent, false) then",
    );
  });
});

describe("send_notifications", () => {
  it("sends a batch through send_notification, granted like it", () => {
    const sql = body();
    expect(sql).toContain(
      'create or replace function "better_supabase"."send_notifications"(events jsonb)',
    );
    expect(sql).toContain("notification => batch_event");
    expect(sql).toContain("hint = 'NOTIFICATION_BATCH_TOO_LARGE'");
    expect(sql).toMatch(
      /grant execute on function "better_supabase"\."send_notifications"\(jsonb\) to /,
    );
  });
});
