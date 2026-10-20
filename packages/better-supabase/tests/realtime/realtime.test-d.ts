import type { StandardSchemaV1 } from "@standard-schema/spec";

import { describe, expectTypeOf, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { useBroadcast } from "../../src/react/index.ts";
import {
  defineTopic,
  type PresenceMember,
  type RealtimeClient,
} from "../../src/realtime/index.ts";
import { defineBucket } from "../../src/storage/index.ts";
import { buckets, schema, topics } from "../fixtures/generated-camel.ts";

const betterSupabase = defineSupabase(schema);

declare const client: RealtimeClient;

declare const title: StandardSchemaV1<
  { title: string },
  { title: string; at: Date }
>;

describe("topic trigger types", () => {
  it("takes when.changed columns of the app table", () => {
    const board = defineTopic("organization:{organizationId}:customers");

    board.trigger("customers", {
      betterSupabase,
      values: { organizationId: "organizationId" },
      when: { changed: ["name", "kvk"] },
    });
    board.trigger("customers", {
      // @ts-expect-error "nope" is not a column of customers, so no overload matches
      betterSupabase,
      values: { organizationId: "organizationId" },
      when: { changed: ["nope"] },
    });
    board.trigger("public.customers", { when: { changed: ["any_column"] } });
  });
});

describe("topic types", () => {
  it("types values, handlers and sends", () => {
    const notifications = defineTopic(topics.notifications, {
      events: { created: title },
    });

    expectTypeOf(notifications.params).toEqualTypeOf<
      readonly ("organizationId" | "userId")[]
    >();
    notifications.subscribe(
      client,
      { organizationId: "o", userId: "u" },
      {
        created: (payload) =>
          expectTypeOf(payload).toEqualTypeOf<{ title: string; at: Date }>(),
      },
    );
    notifications.subscribe(
      client,
      { organizationId: "o", userId: "u" },
      // @ts-expect-error unknown event
      { deleted: () => undefined },
    );
    void notifications.send(
      client,
      { organizationId: "o", userId: "u" },
      "created",
      {
        title: "x",
      },
    );
    void notifications.send(
      client,
      { organizationId: "o", userId: "u" },
      "created",
      {
        // @ts-expect-error wrong payload
        name: "x",
      },
    );
    // @ts-expect-error missing userId
    notifications.topic({ organizationId: "o" });
  });

  it("allows any event without schemas", () => {
    const room = defineTopic("room:{roomId}");
    room.subscribe(
      client,
      { roomId: "r" },
      { anything: (payload) => expectTypeOf(payload).toBeUnknown() },
    );
    void room.send(client, { roomId: "r" }, "ping", { at: 1 });
  });

  it("types presence state from its schema", () => {
    const room = defineTopic("room:{roomId}", { presence: title });

    const subscription = room.subscribe(
      client,
      { roomId: "r" },
      {},
      {
        onPresence: (members) =>
          expectTypeOf(members).toEqualTypeOf<
            readonly PresenceMember<{ title: string; at: Date }>[]
          >(),
      },
    );

    void subscription.track({ title: "x" });
    // @ts-expect-error wrong state
    void subscription.track({ name: "x" });
    expectTypeOf(subscription.members()).toEqualTypeOf<
      readonly PresenceMember<{ title: string; at: Date }>[]
    >();

    const open = defineTopic("open:{roomId}", { presence: true });
    void open.subscribe(client, { roomId: "r" }, {}).track({ anything: 1 });

    const plain = defineTopic("plain:{roomId}").subscribe(
      client,
      { roomId: "r" },
      {},
      // @ts-expect-error no presence on this topic
      { onPresence: () => undefined },
    );

    // @ts-expect-error no presence on this topic
    void plain.track({});
    useBroadcast(room, { roomId: "r" });
  });

  it("keeps generated bucket paths typed", () => {
    const logos = defineBucket(buckets.customerLogos);
    expectTypeOf(logos.params).toEqualTypeOf<
      readonly ("organizationId" | "customerId" | "version")[]
    >();
  });
});
