import { router } from '@better-supabase/example-orpc-api/router';
import { call, ORPCError } from '@orpc/server';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import {
  ACME,
  cleanup,
  createUser,
  OTHER,
  reachable,
  type TestUser,
} from './stack.ts';

describe.skipIf(!(await reachable()))('orpc-api example', () => {
  let acme: TestUser;
  let other: TestUser;
  const rows = cleanup('customers');

  beforeAll(async () => {
    [acme, other] = await Promise.all([createUser(ACME), createUser(OTHER)]);
  });
  afterAll(async () => {
    await rows.run();
    await Promise.all([acme.remove(), other.remove()]);
  });

  const as = (user?: TestUser) => ({
    context: {
      request: new Request('http://api.test/rpc', {
        headers: user ? { authorization: `Bearer ${user.accessToken}` } : {},
      }),
    },
  });

  it('creates, finds and removes customers as the caller', async () => {
    const name = `oRPC e2e ${crypto.randomUUID()}`;
    const created = await call(
      router.customers.create,
      { name, organizationId: ACME },
      as(acme),
    );
    rows.track(created.id);
    expect(created).toMatchObject({
      name,
      organizationId: ACME,
      status: 'lead',
    });

    expect(await call(router.customers.list, { q: name }, as(acme))).toEqual([
      created,
    ]);
    expect(
      await call(router.customers.get, { id: created.id }, as(acme)),
    ).toEqual(created);
    await expect(
      call(router.customers.get, { id: created.id }, as(other)),
    ).rejects.toMatchObject({
      code: 'NOT_FOUND',
    });
    expect(
      await call(router.customers.remove, { id: created.id }, as(acme)),
    ).toEqual({ deleted: true });
  });

  it('maps RLS violations and anonymous callers to ORPCErrors', async () => {
    await expect(
      call(
        router.customers.create,
        { name: 'x', organizationId: ACME },
        as(other),
      ),
    ).rejects.toMatchObject({ code: 'FORBIDDEN', data: { kind: 'forbidden' } });
    const anonymous = await call(router.me, undefined, as()).catch(
      (cause: unknown) => cause,
    );
    expect(anonymous).toBeInstanceOf(ORPCError);
    expect(anonymous).toMatchObject({ code: 'UNAUTHORIZED' });
  });
});
