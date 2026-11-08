import { Worker } from "node:worker_threads";

import type { GeneratedFile, GeneratorInput } from "../../config/index.ts";
import type { WorkerJob, WorkerResult, WorkerStart } from "./worker.ts";

/** One job's outcome: its files, or the error text its generator threw. */
export type PoolOutcome =
  | { readonly ok: true; readonly files: GeneratedFile[] }
  | { readonly ok: false; readonly error: string };

/** The pool could not run: a worker failed to start or died. */
class PoolError extends Error {}

/**
 * Runs `jobs` on up to `size` worker threads and returns their outcomes in the
 * order of `jobs`, whatever order they finish in. Each worker receives `input`
 * once, when it starts. A generator that throws is an outcome; a worker that
 * fails to start or exits early rejects with a `PoolError`, and the caller runs
 * the jobs on the main thread instead.
 */
export function runInWorkers(
  jobs: readonly WorkerJob[],
  input: GeneratorInput,
  options: {
    readonly size: number;
    readonly worker: URL;
    readonly execArgv?: readonly string[];
  },
): Promise<PoolOutcome[]> {
  const outcomes: (PoolOutcome | undefined)[] = jobs.map(() => undefined);
  const size = Math.max(1, Math.min(options.size, jobs.length));
  const workers: Worker[] = [];
  // A worker the pool ends on purpose exits non-zero; that is not a failure.
  const retired = new Set<Worker>();
  let next = 0;
  let done = 0;

  return new Promise<PoolOutcome[]>((resolve, reject) => {
    let failed = false;

    const stop = (): void => {
      for (const worker of workers) {
        retired.add(worker);
        void worker.terminate();
      }
    };

    const fail = (cause: unknown): void => {
      if (failed) {
        return;
      }

      failed = true;
      stop();

      reject(
        new PoolError(cause instanceof Error ? cause.message : String(cause), {
          cause,
        }),
      );
    };

    const feed = (worker: Worker): void => {
      const job = jobs[next];

      if (job === undefined) {
        retired.add(worker);
        void worker.terminate();

        return;
      }

      next += 1;
      // oxlint-disable-next-line unicorn/require-post-message-target-origin -- a worker thread's postMessage takes no origin; 1 finding.
      worker.postMessage(job);
    };

    const spawn = (): void => {
      const start: WorkerStart = { input };

      const worker = new Worker(options.worker, {
        workerData: start,
        ...(options.execArgv === undefined
          ? {}
          : { execArgv: [...options.execArgv] }),
      });

      workers.push(worker);

      worker.on("message", (result: WorkerResult) => {
        outcomes[result.id] = result.ok
          ? { ok: true, files: result.files }
          : { ok: false, error: result.error };
        done += 1;

        if (done === jobs.length) {
          resolve(outcomes.map((outcome) => outcome!));
        }

        feed(worker);
      });

      worker.on("error", fail);

      worker.on("exit", (code) => {
        if (code !== 0 && !retired.has(worker)) {
          fail(
            new Error(`a generator worker exited with code ${String(code)}`),
          );
        }
      });

      feed(worker);
    };

    for (let index = 0; index < size; index += 1) {
      spawn();
    }
  });
}
