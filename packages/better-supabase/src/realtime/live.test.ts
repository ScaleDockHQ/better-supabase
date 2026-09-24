import { describe, expect, it, vi } from 'vitest';

import type { SchemaMeta } from '../schema/types.ts';
import type { RealtimeClient } from './index.ts';

import { defineSupabase } from '../core/define.ts';
import { schema } from '../fixtures/generated-camel.ts';
import { defineSchema } from '../schema/define.ts';
import { liveQuery, liveTopic } from './live.ts';

const meta: SchemaMeta = {
  ...schema.meta,
  realtime: { customers: { tenant: 'organizationId' }, notes: {} },
};
const sb = defineSupabase(defineSchema(meta));
const typed = defineSupabase(schema);

function fakeClient() {
  const channels = new Map<string, Set<() => void>>();
  const client = {
    channel: vi.fn((topic: string, _options: unknown) => {
      const listeners = new Set<() => void>();
      channels.set(topic, listeners);
      const channel = {
        topic,
        on: (_type: string, _filter: unknown, listener: () => void) => {
          listeners.add(listener);
          return channel;
        },
        subscribe: (callback: (status: string) => void) => {
          queueMicrotask(() => callback('SUBSCRIBED'));
          return channel;
        },
      };
      return channel;
    }),
    removeChannel: vi.fn(async (channel: { topic: string }) => {
      channels.delete(channel.topic);
      return 'ok' as const;
    }),
    realtime: { setAuth: vi.fn(async () => undefined) },
  };
  const emit = (topic: string) => {
    for (const listener of channels.get(topic) ?? []) listener();
  };
  return { client: client as unknown as RealtimeClient, raw: client, emit };
}

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

describe('liveTopic', () => {
  it('scopes tenant tables and requires the tenant', () => {
    expect(liveTopic(sb.meta, 'notes')).toBe('bs:t:public.notes');
    expect(liveTopic(sb.meta, 'customers', 'o1')).toBe(
      'bs:t:public.customers:o1',
    );
    expect(() => liveTopic(sb.meta, 'customers')).toThrow(/pass `tenant`/);
  });
});

describe('liveQuery', () => {
  it('watches the broadcasting tables a spec reads and debounces changes', async () => {
    const { client, emit } = fakeClient();
    const onChange = vi.fn();
    const statuses: string[] = [];
    const live = liveQuery(
      sb,
      client,
      typed.spec.customers.findMany({
        include: { notes: true, organization: true },
      }),
      {
        tenant: 'o1',
        debounceMs: 5,
        onChange,
        onStatus: (status) => statuses.push(status),
      },
    );
    expect(live.tables).toEqual(['customers', 'notes']);
    expect(live.unwatched).toEqual(['organizations']);
    await live.ready;

    emit('bs:t:public.customers:o1');
    emit('bs:t:public.notes');
    emit('bs:t:public.notes');
    await wait(20);
    expect(onChange).toHaveBeenCalledTimes(1);
    expect(onChange).toHaveBeenCalledWith(['customers', 'notes']);

    await live.unsubscribe();
    emit('bs:t:public.notes');
    await wait(20);
    expect(onChange).toHaveBeenCalledTimes(1);
    expect(statuses).toEqual(['joining', 'subscribed', 'closed']);
  });

  it('shares one channel per topic and removes it after the last subscriber', async () => {
    const { client, raw, emit } = fakeClient();
    const first = vi.fn();
    const second = vi.fn();
    const a = liveQuery(sb, client, ['notes'], {
      onChange: first,
      debounceMs: 1,
    });
    const b = liveQuery(sb, client, ['notes'], {
      onChange: second,
      debounceMs: 1,
    });
    expect(raw.channel).toHaveBeenCalledTimes(1);
    await Promise.all([a.ready, b.ready]);

    emit('bs:t:public.notes');
    await wait(10);
    expect(first).toHaveBeenCalledTimes(1);
    expect(second).toHaveBeenCalledTimes(1);

    await a.unsubscribe();
    expect(raw.removeChannel).not.toHaveBeenCalled();
    await b.unsubscribe();
    expect(raw.removeChannel).toHaveBeenCalledTimes(1);
  });
});
