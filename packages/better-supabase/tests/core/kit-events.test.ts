import { describe, expect, expectTypeOf, it } from "vitest";

import { EventHub } from "../../src/core/events.ts";
import {
  emitKitEvent,
  type KitEvent,
  kitEventAttributes,
  onKitEvent,
} from "../../src/core/kit-events.ts";
import { decide } from "../../src/core/policy.ts";

describe("kit events", () => {
  it("emits a copy of the data with a time, only when someone listens", () => {
    const events = new EventHub();
    const data = {
      notificationId: "n1",
      kind: "mention",
      recipientIds: ["u1"],
    };
    emitKitEvent(events, "notification.created", data);
    const seen: KitEvent[] = [];
    events.on("kit", (event) => {
      seen.push(event);
    });
    emitKitEvent(events, "notification.created", data, {
      subject: "notifications/n1",
      tenant: "t1",
    });
    expect(seen).toHaveLength(1);
    expect(seen[0]).toMatchObject({
      type: "notification.created",
      subject: "notifications/n1",
      tenant: "t1",
      data,
    });
    expect(seen[0]!.data).not.toBe(data);
    expect(seen[0]!.time).toBeInstanceOf(Temporal.Instant);
  });

  it("filters by type or prefix pattern", () => {
    const events = new EventHub();
    const types: string[] = [];
    const stop = onKitEvent({ events }, "invitation.*", (event) => {
      expectTypeOf(event.type).toEqualTypeOf<
        | "invitation.created"
        | "invitation.resent"
        | "invitation.accepted"
        | "invitation.declined"
        | "invitation.revoked"
      >();
      types.push(event.type);
    });
    onKitEvent({ events }, "org.created", (event) => {
      expectTypeOf(event.data.organizationId).toBeString();
      types.push(event.type);
    });
    emitKitEvent(events, "invitation.accepted", { invitationId: "i1" });
    emitKitEvent(events, "org.created", { organizationId: "o1" });
    emitKitEvent(events, "org.switched", { organizationId: "o1" });
    stop();
    emitKitEvent(events, "invitation.revoked", { invitationId: "i1" });
    expect(types).toEqual(["invitation.accepted", "org.created"]);
  });

  it("names the attributes an event carries", () => {
    expect(
      kitEventAttributes({
        type: "support.started",
        data: { sessionId: "s1", adminId: "a", targetUserId: "u" },
        time: Temporal.Now.instant(),
      }),
    ).toEqual({
      "better_supabase.kit.event": "support.started",
      "better_supabase.support.session_id": "s1",
    });
  });
});

describe("decide", () => {
  it("allows only true and fails closed", async () => {
    expect(await decide(() => true, [], false)).toEqual({ allowed: true });
    expect(await decide(() => Promise.resolve(true), [], false)).toEqual({
      allowed: true,
    });
    // SAFETY: a JavaScript caller can return any value.
    const loose = (() => "yes") as unknown as () => boolean;
    expect(await decide(loose, [], true)).toEqual({
      allowed: false,
      reason: "denied",
    });
    const cause = new Error("down");
    expect(
      await decide(
        (id: string) => {
          expect(id).toBe("u1");
          throw cause;
        },
        ["u1"],
        true,
      ),
    ).toEqual({ allowed: false, reason: "threw", cause });
    expect(await decide(() => Promise.reject(cause), [], true)).toMatchObject({
      reason: "threw",
    });
  });

  it("applies the default without a policy", async () => {
    expect(await decide(undefined, [], true)).toEqual({ allowed: true });
    expect(await decide(undefined, [], false)).toEqual({
      allowed: false,
      reason: "denied",
    });
  });
});
