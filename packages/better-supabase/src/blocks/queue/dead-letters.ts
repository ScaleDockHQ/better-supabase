import type { DeadJobRow, QueueProvider } from "./backends.ts";
import type { Job } from "./types.ts";

/**
 * Where `withDeadLetters` sends a job past its last attempt. `listDead` and
 * `retryDead` back `jobs.listDead` and `jobs.retryDead` when the wrapped
 * backend keeps no dead letters.
 */
export interface DeadLetterSink {
  onDead(job: Job, error: string): PromiseLike<void> | void;
  listDead?(
    queue: string,
    limit: number,
    before: number | undefined,
  ): Promise<readonly DeadJobRow[]>;
  retryDead?(
    queue: string,
    ids: readonly number[] | undefined,
    limit: number,
  ): Promise<number>;
}

/**
 * Hands every job `provider` gives up on to `sink`, for backends that drop a
 * message after its last attempt (Vercel Queues keeps no dead letters). The
 * sink's error never changes the result: the job stays dead either way.
 */
export function withDeadLetters(
  provider: QueueProvider,
  sink: DeadLetterSink,
): QueueProvider {
  const listDead =
    sink.listDead?.bind(sink) ?? provider.listDead?.bind(provider);

  const retryDead =
    sink.retryDead?.bind(sink) ?? provider.retryDead?.bind(provider);

  return {
    ...provider,
    name: `${provider.name}+dead-letters`,
    async fail(job, error, retryIn) {
      const outcome = await provider.fail(job, error, retryIn);

      if (outcome === "dead") {
        try {
          await sink.onDead(job, error);
        } catch {
          // The job is already acknowledged; a failing sink can't revive it.
        }
      }

      return outcome;
    },
    ...(listDead === undefined ? {} : { listDead }),
    ...(retryDead === undefined ? {} : { retryDead }),
  };
}
