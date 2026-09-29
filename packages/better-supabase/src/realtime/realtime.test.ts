import type { StandardSchemaV1 } from '@standard-schema/spec';

import { describe, expect, it, vi } from 'vitest';

import { defineSupabase } from '../core/define.ts';
import { DbException } from '../core/errors.ts';
import { schema, topics } from '../fixtures/generated-camel.ts';
import { defineTopic, type RealtimeClient, rowChange } from './index.ts';

const sb = defineSupabase(schema);

const title: StandardSchemaV1<unknown, { title: string }> = {
  '~standard': {
    version: 1,
    vendor: 'test',
    validate: (value) =>
      typeof (value as { title?: unknown } | null)?.title === 'string'
        ? { value: { title: (value as { title: string }).title } }
        : {
            issues: [
              { message: 'title is required', path: [{ key: 'title' }] },
            ],
          },
  },
};

type Listener = (message: { event: string; payload: unknown }) => void;

function fakeClient(status: 'SUBSCRIBED' | 'CHANNEL_ERROR' = 'SUBSCRIBED') {
  const listeners: Listener[] = [];
  const removed: unknown[] = [];
  const channel = {
    on: (_type: string, _filter: unknown, listener: Listener) => {
      listeners.push(listener);
      return channel;
    },
    subscribe: (callback: (status: string, error?: Error) => void) => {
      queueMicrotask(() =>
        callback(
          status,
          status === 'SUBSCRIBED' ? undefined : new Error('Unauthorized'),
        ),
      );
      return channel;
    },
    httpSend: vi.fn(async () => ({ success: true as const })),
  };
  const client = {
    channel: vi.fn(() => channel),
    removeChannel: vi.fn(async (value: unknown) => {
      removed.push(value);
      return 'ok' as const;
    }),
    realtime: { setAuth: vi.fn(async () => undefined) },
  };
  const emit = (event: string, payload: unknown) => {
    for (const listener of listeners) listener({ event, payload });
  };
  return {
    client: client as unknown as RealtimeClient,
    raw: client,
    channel,
    emit,
    removed,
  };
}

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

describe('defineTopic', () => {
  const notifications = defineTopic(topics.notifications, {
    events: { created: title },
    send: true,
  });

  it('builds and matches topic names', () => {
    expect(notifications.topic({ orgId: 'o1', userId: 'u1' })).toBe(
      'org:o1:notifications:u1',
    );
    expect(notifications.match('org:o1:notifications:u1')).toEqual({
      orgId: 'o1',
      userId: 'u1',
    });
    expect(notifications.match('org:o1:notifications')).toBeNull();
    expect(() => notifications.topic({ orgId: 'o:1', userId: 'u1' })).toThrow(
      DbException,
    );
    expect(notifications.name).toBe('org_notifications');
  });

  it('generates policies with tenant and owner checks', () => {
    const sql = notifications.sql();
    expect(sql).toContain(
      'create policy "bs_topic_org_notifications_receive" on realtime.messages for select to authenticated',
    );
    expect(sql).toContain(
      'create policy "bs_topic_org_notifications_send" on realtime.messages for insert to authenticated',
    );
    expect(sql).toContain(
      "(select realtime.topic()) ~ '^org:[^:]+:notifications:[^:]+$'",
    );
    expect(sql).toContain(
      "split_part((select realtime.topic()), ':', 2) = (coalesce((select auth.jwt()) ->> 'org_id'",
    );
    expect(sql).toContain(
      "split_part((select realtime.topic()), ':', 4) = (select auth.uid())::text",
    );
    const open = defineTopic('room:{roomId}').sql();
    expect(open).not.toContain('split_part');
    expect(open).not.toContain('for insert');
  });

  it('generates a row-change trigger with database column names', () => {
    const sql = defineTopic(topics.customers).triggerSql(sb, 'customers', {
      values: { orgId: 'organizationId' },
    });
    expect(sql).toContain(
      'create or replace function "public"."bs_broadcast_org_customers_customers"()',
    );
    expect(sql).toContain(
      "'org:' || rec.\"organization_id\"::text || ':customers',",
    );
    expect(sql).toContain(
      'create trigger "bs_broadcast_org_customers" after insert or update or delete on "public"."customers"',
    );
  });

  it('dispatches validated payloads and disposes the channel', async () => {
    const { client, raw, emit, removed } = fakeClient();
    const created = vi.fn();
    const other = vi.fn();
    const onInvalid = vi.fn();
    {
      using subscription = notifications.subscribe(
        client,
        { orgId: 'o1', userId: 'u1' },
        { created, '*': other },
        { onInvalid },
      );
      await subscription.ready;
      expect(raw.realtime.setAuth).toHaveBeenCalled();
      expect(raw.channel).toHaveBeenCalledWith('org:o1:notifications:u1', {
        config: { private: true, broadcast: { self: false } },
      });
      emit('created', { title: 'Hi', extra: 1 });
      emit('created', { nope: true });
      emit('deleted', { id: 1 });
      await flush();
    }
    expect(created).toHaveBeenCalledWith(
      { title: 'Hi' },
      {
        event: 'created',
        payload: { title: 'Hi', extra: 1 },
        topic: 'org:o1:notifications:u1',
      },
    );
    expect(onInvalid).toHaveBeenCalledWith(
      expect.objectContaining({ event: 'created' }),
      [{ message: 'title is required', path: ['title'] }],
    );
    expect(other).toHaveBeenCalledWith(
      { id: 1 },
      expect.objectContaining({ event: 'deleted' }),
    );
    expect(removed).toHaveLength(1);
  });

  it('rejects ready when the join is refused', async () => {
    const { client } = fakeClient('CHANNEL_ERROR');
    const statuses: string[] = [];
    const subscription = notifications.subscribe(
      client,
      { orgId: 'o1', userId: 'u1' },
      {},
      { onStatus: (status) => statuses.push(status) },
    );
    await expect(subscription.ready).rejects.toThrow('Unauthorized');
    expect(statuses).toEqual(['joining', 'error']);
  });

  it('validates before sending', async () => {
    const { client, channel } = fakeClient();
    const invalid = await notifications.send(
      client,
      { orgId: 'o1', userId: 'u1' },
      'created',
      {},
    );
    expect(invalid.error?.kind).toBe('validation');
    expect(channel.httpSend).not.toHaveBeenCalled();
    await notifications
      .send(client, { orgId: 'o1', userId: 'u1' }, 'created', { title: 'Hi' })
      .orThrow();
    expect(channel.httpSend).toHaveBeenCalledWith('created', { title: 'Hi' });
  });
});

describe('rowChange', () => {
  it('maps broadcast_changes payloads to app casing', () => {
    const message = {
      event: 'UPDATE',
      topic: 'org:o1:customers',
      payload: {
        schema: 'public',
        table: 'customers',
        operation: 'UPDATE',
        record: { id: 'c1', organization_id: 'o1', name: 'New' },
        old_record: { id: 'c1', name: 'Old' },
      },
    };
    expect(rowChange(sb, 'customers', message)).toEqual({
      operation: 'UPDATE',
      table: 'customers',
      record: { id: 'c1', organizationId: 'o1', name: 'New' },
      oldRecord: { id: 'c1', name: 'Old' },
    });
    expect(rowChange(sb, 'notes', message)).toBeNull();
  });
});
