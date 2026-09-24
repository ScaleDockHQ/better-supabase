import type { StandardSchemaV1 } from '@standard-schema/spec';

import { describe, expectTypeOf, it } from 'vitest';

import { buckets, topics } from '../fixtures/generated-camel.ts';
import { defineBucket } from '../storage/index.ts';
import { defineTopic, type RealtimeClient } from './index.ts';

declare const client: RealtimeClient;
declare const title: StandardSchemaV1<
  { title: string },
  { title: string; at: Date }
>;

describe('topic types', () => {
  it('types values, handlers and sends', () => {
    const notifications = defineTopic(topics.notifications, {
      events: { created: title },
    });
    expectTypeOf(notifications.params).toEqualTypeOf<
      readonly ('orgId' | 'userId')[]
    >();
    notifications.subscribe(
      client,
      { orgId: 'o', userId: 'u' },
      {
        created: (payload) =>
          expectTypeOf(payload).toEqualTypeOf<{ title: string; at: Date }>(),
      },
    );
    notifications.subscribe(
      client,
      { orgId: 'o', userId: 'u' },
      // @ts-expect-error unknown event
      { deleted: () => undefined },
    );
    void notifications.send(client, { orgId: 'o', userId: 'u' }, 'created', {
      title: 'x',
    });
    void notifications.send(client, { orgId: 'o', userId: 'u' }, 'created', {
      // @ts-expect-error wrong payload
      name: 'x',
    });
    // @ts-expect-error missing userId
    notifications.topic({ orgId: 'o' });
  });

  it('allows any event without schemas', () => {
    const room = defineTopic('room:{roomId}');
    room.subscribe(
      client,
      { roomId: 'r' },
      { anything: (payload) => expectTypeOf(payload).toBeUnknown() },
    );
    void room.send(client, { roomId: 'r' }, 'ping', { at: 1 });
  });

  it('keeps generated bucket paths typed', () => {
    const logos = defineBucket(buckets.customerLogos);
    expectTypeOf(logos.params).toEqualTypeOf<
      readonly ('orgId' | 'customerId' | 'version')[]
    >();
  });
});
