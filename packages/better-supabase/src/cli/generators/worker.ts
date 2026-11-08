import { parentPort, workerData } from "node:worker_threads";

import type {
  GeneratedFile,
  Generator,
  GeneratorInput,
  GeneratorModule,
} from "../../config/index.ts";

/** What `gen` hands a worker once, when it starts. */
export interface WorkerStart {
  readonly input: GeneratorInput;
}

/** One generator to run, by the module that builds it. */
export interface WorkerJob {
  readonly id: number;
  readonly name: string;
  readonly version: string;
  readonly module: GeneratorModule;
  readonly options: unknown;
}

/** What a worker answers: the files, or the text of the error. */
export type WorkerResult =
  | { readonly id: number; readonly ok: true; readonly files: GeneratedFile[] }
  | { readonly id: number; readonly ok: false; readonly error: string };

const isGenerator = (value: unknown): value is Generator =>
  typeof value === "object" &&
  value !== null &&
  "generate" in value &&
  typeof value.generate === "function" &&
  "name" in value &&
  typeof value.name === "string" &&
  "version" in value &&
  typeof value.version === "string";

const isFactory = (value: unknown): value is (options: unknown) => unknown =>
  typeof value === "function";

const textOf = (cause: unknown): string =>
  cause instanceof Error ? cause.message : String(cause);

async function load(job: WorkerJob): Promise<Generator> {
  // The specifier names the generator's own module, which only the job knows.
  const loaded: unknown = await import(job.module.specifier);

  const factory: unknown =
    typeof loaded === "object" && loaded !== null
      ? Object.entries(loaded).find(([key]) => key === job.module.export)?.[1]
      : undefined;

  if (!isFactory(factory)) {
    throw new TypeError(
      `${job.module.specifier} does not export a function named "${job.module.export}"`,
    );
  }

  const built: unknown = factory(job.options ?? undefined);

  if (!isGenerator(built)) {
    throw new TypeError(
      `${job.module.specifier} export "${job.module.export}" did not return a generator`,
    );
  }

  if (built.name !== job.name || built.version !== job.version) {
    throw new TypeError(
      `${job.module.specifier} built "${built.name}" ${built.version}, not "${job.name}" ${job.version}`,
    );
  }

  return built;
}

/**
 * Builds the job's generator from its module and runs it. A generator that
 * throws, or a module that does not build one, is a result, not an exception.
 */
export async function runJob(
  job: WorkerJob,
  input: GeneratorInput,
): Promise<WorkerResult> {
  try {
    const generator = await load(job);
    const files = await generator.generate(input);

    return { id: job.id, ok: true, files: [...files] };
  } catch (cause) {
    return { id: job.id, ok: false, error: textOf(cause) };
  }
}

/** The part of a message port the worker uses. */
export interface JobPort {
  on(event: "message", listener: (job: WorkerJob) => void): unknown;
  postMessage(result: WorkerResult): void;
}

/** Answers each job posted to `port` with its result, using `input`. */
export function serve(port: JobPort, input: GeneratorInput): void {
  port.on("message", (job) => {
    void runJob(job, input).then((result) => {
      port.postMessage(result);
    });
  });
}

if (parentPort !== null) {
  // SAFETY: `gen` starts this worker with a WorkerStart in workerData.
  serve(parentPort, (workerData as WorkerStart).input);
}
