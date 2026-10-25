import { createBlocks, sqlTransport } from "better-supabase/blocks";
import { customFieldsBlock } from "better-supabase/blocks/custom-fields";
import {
  createNotifications,
  notificationsBlock,
} from "better-supabase/blocks/notifications";
import { remindersBlock } from "better-supabase/blocks/reminders";
import { stateMachineBlock } from "better-supabase/blocks/state-machine";
import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { received, watching, workspace } from "./flow.ts";
import { NOTIFICATION_TYPES } from "./notification-types.ts";
import { scheduling } from "./recipes.ts";
import { dbUrl, reachable, withRecipe } from "./stack.ts";

const live = await reachable();

const BOOKING =
  "insert into recipe_scheduling.bookings (organization_id, title, starts_at) values ($1, 'Kickoff call', '2026-10-20T09:00:00Z') returning id";

describe.skipIf(!live)("scheduling recipe", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });

  afterAll(() => pool.end());

  it("confirms a booking, records its fields and reminds once", async () => {
    await withRecipe(pool, scheduling, async (s) => {
      const { owner, member, organizationId, subjectId } = await workspace(
        s,
        "booking",
        BOOKING,
      );

      const watchers = await watching(s);

      const { customFields, reminders, stateMachine } = createBlocks(
        { transport: sqlTransport(s.sql), tenant: organizationId },
        {
          notifications: notificationsBlock.using((options) =>
            createNotifications({ ...options, types: NOTIFICATION_TYPES }),
          ),
          customFields: customFieldsBlock,
          reminders: remindersBlock.with({ notification: "reminder.due" }),
          stateMachine: stateMachineBlock,
        },
      );

      await s.as(owner);
      await stateMachine
        .transition({ type: "booking", id: subjectId }, "confirmed")
        .orThrow();

      const room = await customFields
        .saveDefinition("booking", "room", "Room", "text")
        .orThrow();

      await customFields
        .setValue({ type: "booking", id: subjectId }, room.id, "Atlas")
        .orThrow();

      const reminder = await reminders
        .upsert({ type: "booking", id: subjectId }, 15)
        .orThrow();

      await watchers.relay();
      await s.service();

      const delivery = {
        reminderId: reminder.id,
        occurrenceAt: Temporal.Instant.from("2026-10-20T09:00:00Z"),
        organizationId,
        userId: owner.id,
        subject: { type: "booking", id: subjectId },
      };

      expect(await reminders.deliver(delivery).orThrow()).toBe(true);
      expect(await reminders.deliver(delivery).orThrow()).toBe(false);

      expect(await received(s, member, subjectId)).toEqual([
        "reminder.due",
        "subject.field_changed",
        "subject.moved",
      ]);
      expect(await received(s, owner, subjectId)).toEqual(["reminder.due"]);
      await s.as(owner);
      expect(
        await stateMachine.transition(
          { type: "booking", id: subjectId },
          "requested",
        ),
      ).toMatchObject({ ok: false });
    });
  });
});
