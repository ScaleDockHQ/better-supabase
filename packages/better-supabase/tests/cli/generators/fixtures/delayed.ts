// A generator a worker thread loads by file URL. It uses no import, so the
// worker needs nothing but this file.

interface Options {
  readonly id: string;
  readonly delay?: number;
  readonly fail?: string;
}

interface File {
  readonly path: string;
  readonly contents: string;
}

interface Delayed {
  readonly apiVersion: 2;
  readonly name: string;
  readonly version: string;
  readonly options: Options;
  readonly pure: true;
  readonly workerSafe: true;
  generate(input: { readonly meta: unknown }): Promise<File[]>;
}

const wait = (ms: number): Promise<void> =>
  new Promise((done) => {
    setTimeout(done, ms);
  });

export function delayed(options: Options): Delayed {
  return {
    apiVersion: 2,
    name: `delayed-${options.id}`,
    version: "1.0.0",
    options,
    pure: true,
    workerSafe: true,
    async generate(input) {
      await wait(options.delay ?? 0);

      if (options.fail !== undefined) {
        throw new Error(options.fail);
      }

      return [
        {
          path: `out/${options.id}.json`,
          contents: JSON.stringify({ id: options.id, meta: input.meta }),
        },
      ];
    },
  };
}

/** A generator whose `generate` throws a string, not an `Error`. */
export function throwsText(): Delayed {
  return {
    apiVersion: 2,
    name: "delayed-a",
    version: "1.0.0",
    options: { id: "a" },
    pure: true,
    workerSafe: true,
    generate() {
      // oxlint-disable-next-line typescript/only-throw-error -- the test throws a string to reach the non-Error branch; 1 finding.
      throw "plain text";
    },
  };
}

/** An export that builds something that is not a generator. */
export function notAGenerator(): Record<string, never> {
  return {};
}
