import type { SupabaseClient } from '@supabase/supabase-js';
import type { QueryClient } from '@tanstack/react-query';

import { describe, expectTypeOf, it } from 'vitest';

import type { AuthResolver } from '../auth/resolve.ts';
import type { Generator } from '../config/index.ts';
import type { EventSink } from '../events/index.ts';
import type { Operation } from '../ir/types.ts';
import type { CacheAdapter } from './cache.ts';
import type { Compiler } from './compiler.ts';
import type { Executor } from './executor.ts';
import type { Logger } from './logger.ts';
import type { AnyPlugin } from './plugin.ts';
import type { AsyncResult } from './result.ts';

import { jsonSchema } from '../config/index.ts';
import { httpSink } from '../events/index.ts';
import { schema } from '../fixtures/generated-camel.ts';
import { valibot } from '../generators/valibot.ts';
import { zod } from '../generators/zod.ts';
import { nextCache } from '../next/index.ts';
import { softDelete } from '../plugins/soft-delete/index.ts';
import { tenant } from '../plugins/tenant/index.ts';
import { timestamps } from '../plugins/timestamps/index.ts';
import { postgresExecutor, sqlCompiler } from '../postgres/index.ts';
import { queryCache } from '../query/index.ts';
import { memoryCache } from './cache.ts';
import { postgrestCompiler } from './compiler.ts';
import { defineRepository } from './define-repository.ts';
import { defineSupabase } from './define.ts';
import { consoleLogger, silentLogger } from './logger.ts';
import { postgrestExecutor } from './postgrest-executor.ts';

declare const client: SupabaseClient;
declare const queryClient: QueryClient;

describe('extension interfaces', () => {
  it('are implemented by the first-party extensions', () => {
    expectTypeOf(postgrestExecutor(client)).toExtend<Executor>();
    expectTypeOf(postgresExecutor).returns.toExtend<Executor>();
    expectTypeOf(postgrestCompiler).toExtend<Compiler<unknown>>();
    expectTypeOf(sqlCompiler).toExtend<Compiler<unknown>>();
    expectTypeOf(memoryCache()).toExtend<CacheAdapter>();
    expectTypeOf(nextCache()).toExtend<CacheAdapter>();
    expectTypeOf(queryCache(queryClient)).toExtend<CacheAdapter>();
    expectTypeOf(httpSink).returns.toExtend<EventSink>();
    expectTypeOf(consoleLogger).toExtend<Logger>();
    expectTypeOf(silentLogger).toExtend<Logger>();
    expectTypeOf(zod()).toExtend<Generator>();
    expectTypeOf(valibot()).toExtend<Generator>();
    expectTypeOf(jsonSchema()).toExtend<Generator>();
    expectTypeOf(timestamps()).toExtend<AnyPlugin>();
    expectTypeOf<AuthResolver['resolve']>()
      .parameter(0)
      .toEqualTypeOf<Request>();
  });

  it('keeps Executor.batch optional, so existing executors still conform', () => {
    const minimal: Executor = {
      name: 'minimal',
      execute: () => Promise.reject(new Error('unused')),
    };
    expectTypeOf(minimal).toExtend<Executor>();
    expectTypeOf<NonNullable<Executor['batch']>>()
      .parameter(0)
      .toEqualTypeOf<readonly Operation[]>();
  });
});

describe('defineRepository', () => {
  const sb = defineSupabase(schema).use(softDelete()).use(tenant());
  const tags = defineRepository(sb, 'tags', (base) => ({
    named: (name: string) =>
      base.findFirst({ where: { name }, select: ['id', 'name'] }),
  }));
  const db = sb.use(tags).connect(client);

  it('types methods on the target table only', () => {
    expectTypeOf(db.tags.named).parameters.toEqualTypeOf<[name: string]>();
    expectTypeOf(db.tags.named('x')).toEqualTypeOf<
      AsyncResult<{ id: string; name: string } | null>
    >();
    expectTypeOf(db.customers).not.toHaveProperty('named');
  });

  it('keeps plugin extensions on the base repository', () => {
    defineRepository(sb, 'customers', (base) => {
      expectTypeOf(base).toHaveProperty('restore');
      return {};
    });
  });

  it('accepts only known tables', () => {
    // @ts-expect-error unknown table
    defineRepository(sb, 'nope', () => ({}));
  });
});
