/** The one pool method the reader uses, so a test can pass a fake. */
export interface PollingPool {
  readonly query: (
    text: string,
    values: unknown[],
  ) => Promise<{ readonly rows: ChunkRow[] }>;
}

export interface ChunkRow {
  readonly id: string;
  readonly data: Buffer;
  readonly eof: boolean;
}

/** The sleep between reads of a stream that is still open. */
export const DEFAULT_STREAM_POLL_MS = 100;

/**
 * A stream reader that polls `workflow.workflow_stream_chunks` instead of
 * waiting for `NOTIFY`, for connections through the transaction pooler (no
 * `LISTEN`). It has the same offsets as `@workflow/world-postgres`: a start
 * index skips that many data chunks, a negative one counts back from the data
 * stored when the read starts, and the first `eof` chunk ends the stream.
 */
export function pollingStreamReader(
  pool: PollingPool,
  intervalMs: number = DEFAULT_STREAM_POLL_MS,
): {
  readonly get: (
    name: string,
    startIndex?: number,
  ) => ReadableStream<Uint8Array>;
  /** Ends every read still waiting, so no timer keeps the process alive. */
  readonly close: () => void;
} {
  const active = new Set<(error?: Error) => void>();

  const read = async (name: string, after: string): Promise<ChunkRow[]> => {
    const result = await pool.query(
      `select id, data, eof from workflow.workflow_stream_chunks
       where stream_id = $1 and id > $2 order by id`,
      [name, after],
    );

    return result.rows;
  };

  const get = (
    name: string,
    startIndex?: number,
  ): ReadableStream<Uint8Array> => {
    let stopped = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let wake: (() => void) | undefined;

    const sleep = (): Promise<void> =>
      new Promise((resolve) => {
        wake = resolve;
        timer = setTimeout(resolve, intervalMs);
      });

    let ctrl: ReadableStreamDefaultController<Uint8Array> | undefined;

    const isStopped = (): boolean => stopped;

    const stop = (error?: Error): void => {
      if (error !== undefined && !stopped) {
        ctrl?.error(error);
      }

      stopped = true;
      active.delete(stop);
      clearTimeout(timer);
      wake?.();
    };

    active.add(stop);

    return new ReadableStream<Uint8Array>({
      async start(controller) {
        ctrl = controller;
        let last = "";
        let skip = startIndex ?? 0;
        let first = true;

        try {
          while (!isStopped()) {
            const rows = await read(name, last);

            if (first && skip < 0) {
              const end = rows.findIndex((row) => row.eof);
              const count = end === -1 ? rows.length : end;
              skip = Math.max(0, count + skip);
            }

            first = false;

            for (const row of rows) {
              last = row.id;

              if (skip > 0 && !row.eof) {
                skip -= 1;
                continue;
              }

              if (row.data.byteLength > 0) {
                controller.enqueue(new Uint8Array(row.data));
              }

              if (row.eof) {
                stop();
                controller.close();

                return;
              }
            }

            await sleep();
          }
        } catch (error) {
          if (!stopped) {
            controller.error(error);
          }
        }
      },
      cancel() {
        stop();
      },
    });
  };

  return {
    get,
    close() {
      for (const stop of [...active]) {
        stop(new Error("Cannot read stream: the World has been closed"));
      }
    },
  };
}
