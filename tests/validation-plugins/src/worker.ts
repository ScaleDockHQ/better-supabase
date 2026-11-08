import type { GeneratorInput } from "better-supabase/generators";

import { parentPort, workerData } from "node:worker_threads";

import { acmeTables } from "./acme-generator.ts";

// A worker gets the input as a structured clone, so the generator can read
// nothing that a closure in the config file would have held.
// SAFETY: the test posts a `GeneratorInput` as `workerData`.
const input = workerData as GeneratorInput;

const files = await acmeTables().generate(input);

// oxlint-disable-next-line unicorn/require-post-message-target-origin -- parentPort is a MessagePort, which takes no origin (1 finding).
parentPort?.postMessage(files);
