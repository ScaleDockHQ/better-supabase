import { describe, expect, it } from 'vitest';

import { capturingClient } from '../fixtures/client.ts';
import { schema } from '../fixtures/generated-camel.ts';
import { settle } from '../server/respond.ts';
import { defineSupabase } from './define.ts';
import {
  type DbError,
  DbException,
  dbError,
  dbErrorOf,
  isConflict,
} from './errors.ts';
import {
  AsyncResult,
  err,
  fromBetterResult,
  ok,
  toBetterResult,
} from './result.ts';

class StandInOk<T> {
  readonly status = 'ok';
  readonly value: T;
  constructor(value: T) {
    this.value = value;
  }
}
class StandInErr<E> {
  readonly status = 'error';
  readonly error: E;
  constructor(error: E) {
    this.error = error;
  }
}
const Result = {
  ok: <T>(value: T) => new StandInOk(value),
  err: <E>(error: E) => new StandInErr(error),
};

class AppError extends Error {
  readonly error: DbError;
  constructor(error: DbError) {
    super(`app: ${error.message}`, { cause: error });
    this.error = error;
  }
}
const toAppError = (error: DbError) => new AppError(error);

const conflict = () =>
  capturingClient(() => ({
    status: 409,
    body: { code: '23505', message: 'duplicate key value' },
  }));

describe('sb.mapError', () => {
  it('makes .orThrow() throw the mapped error; results keep the DbError', async () => {
    const db = defineSupabase(schema)
      .mapError(toAppError)
      .connect(conflict().client);
    const result = await db.customers.create({
      name: 'Acme',
      organizationId: 'o1',
    });
    expect(result.ok).toBe(false);
    expect(result.error?.kind).toBe('conflict');

    const thrown = await db.customers
      .create({ name: 'Acme', organizationId: 'o1' })
      .orThrow()
      .catch((error: unknown) => error);
    expect(thrown).toBeInstanceOf(AppError);
    expect((thrown as AppError).error.kind).toBe('conflict');
  });

  it('survives map, mapError and andThen, and a factory still wins', async () => {
    const db = defineSupabase(schema)
      .mapError(toAppError)
      .connect(conflict().client);
    const chained = db.customers
      .create({ name: 'Acme', organizationId: 'o1' })
      .map((row) => row.id)
      .mapError((error) => ({ ...error, message: 'renamed' }))
      .andThen((id) => AsyncResult.ok(id));
    await expect(chained.orThrow()).rejects.toThrow('app: renamed');
    await expect(
      db.customers
        .create({ name: 'Acme', organizationId: 'o1' })
        .orThrow(() => new Error('factory')),
    ).rejects.toThrow('factory');
  });

  it('keeps the DbError reachable through cause for adapters and guards', async () => {
    const db = defineSupabase(schema)
      .mapError(toAppError)
      .connect(conflict().client);
    const thrown: unknown = await db.customers
      .create({ name: 'Acme', organizationId: 'o1' })
      .orThrow()
      .catch((error: unknown) => error);
    expect(dbErrorOf(thrown)?.kind).toBe('conflict');
    expect(isConflict(thrown)).toBe(true);
    const settled = await settle(() =>
      db.customers.create({ name: 'Acme', organizationId: 'o1' }).orThrow(),
    );
    expect(!settled.ok && settled.error.kind).toBe('conflict');
  });

  it('throws a DbException without a mapper', async () => {
    const db = defineSupabase(schema).connect(conflict().client);
    await expect(
      db.customers.create({ name: 'Acme', organizationId: 'o1' }).orThrow(),
    ).rejects.toBeInstanceOf(DbException);
  });
});

describe('toBetterResult', () => {
  it('builds Ok and Err with the namespace passed in', () => {
    const good = toBetterResult(ok(1), Result);
    expect(good).toBeInstanceOf(StandInOk);
    expect(good).toMatchObject({ status: 'ok', value: 1 });

    const failure = dbError('not_found', 'gone');
    expect(toBetterResult(err(failure), Result)).toMatchObject({
      status: 'error',
      error: failure,
    });
    const mapped = toBetterResult(err(failure), Result, toAppError);
    expect(mapped.status === 'error' && mapped.error).toBeInstanceOf(AppError);
  });

  it('awaits an AsyncResult and uses the mapper of sb.mapError', async () => {
    const db = defineSupabase(schema)
      .mapError(toAppError)
      .connect(conflict().client);
    const mapped = await toBetterResult(
      db.customers.create({ name: 'Acme', organizationId: 'o1' }),
      Result,
    );
    expect(mapped.status === 'error' && mapped.error).toBeInstanceOf(AppError);

    const plain = await toBetterResult(AsyncResult.ok('x'), Result);
    expect(plain).toMatchObject({ status: 'ok', value: 'x' });
  });
});

describe('fromBetterResult', () => {
  it('converts by status and keeps DbErrors', () => {
    expect(fromBetterResult(Result.ok(2))).toEqual(ok(2));
    const failure = dbError('conflict', 'taken');
    expect(fromBetterResult(Result.err(failure))).toEqual(err(failure));
  });

  it('turns other errors into DbErrors', () => {
    const converted = fromBetterResult(Result.err(new Error('boom')));
    expect(converted.error).toMatchObject({
      kind: 'unexpected',
      message: 'boom',
    });
    const custom = fromBetterResult(Result.err('nope'), () =>
      dbError('forbidden', 'mapped'),
    );
    expect(custom.error?.kind).toBe('forbidden');
  });

  it('round-trips', () => {
    const original = ok({ id: 'c1' });
    expect(fromBetterResult(toBetterResult(original, Result))).toEqual(
      original,
    );
  });
});
