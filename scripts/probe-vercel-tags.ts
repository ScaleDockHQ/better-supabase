// Asks a Vercel preview of apps/examples/nextjs how tag invalidation and the
// kept store behave, and prints the tables for ADRs 1207 and 1228 and the
// Vercel cache docs page. Set BSB_TAG_PROBE_SECRET on the preview, then run:
//   BSB_TAG_PROBE_SECRET=... node scripts/probe-vercel-tags.ts https://<preview>.vercel.app [--bypass <token>] [--second]
// `--second` reads the kept entry from up to 10 more requests, to reach another
// instance. `--local` runs the kept steps on memoryKeptStore() instead, with
// no preview.
import { argv, env, exit } from "node:process";

import type {
  Burst,
  KeptRead,
  KeptWrite,
  Latency,
  ProbeStore,
  VersionRead,
} from "../apps/examples/nextjs/src/lib/kept-probe.ts";

import {
  burst,
  keptRead,
  keptWrite,
  latency,
  versionRead,
} from "../apps/examples/nextjs/src/lib/kept-probe.ts";
import { memoryKeptStore } from "../packages/better-supabase/src/core/kept-cache.ts";

interface Step {
  readonly method: string;
  readonly stored: boolean;
  readonly goneAtOnce: boolean;
  readonly goneAfter: number | null;
  readonly error: string | null;
}

interface Answer {
  readonly steps: readonly Step[];
  readonly limits: readonly { count: number; error: string | null }[];
  readonly oversizedTag: { rejects: boolean; error: string | null };
}

interface ProbeBody {
  readonly step:
    | "tags"
    | "kept-write"
    | "kept-read"
    | "version"
    | "latency"
    | "burst";
  readonly key?: string;
}

interface Kept {
  readonly write: KeptWrite;
  readonly reads: readonly KeptRead[];
  readonly version: VersionRead;
  readonly latency: Latency;
  readonly burst: Burst;
}

const args = argv.slice(2);
const local = args.includes("--local");
const second = args.includes("--second");
const base = args.find((arg) => arg.startsWith("http"))?.replace(/\/$/, "");
const bypassIndex = args.indexOf("--bypass");
const bypass = bypassIndex === -1 ? undefined : args[bypassIndex + 1];
const secret = env["BSB_TAG_PROBE_SECRET"];

const printKept = (where: string, kept: Kept): void => {
  console.log("");
  console.log(`| Kept store step (${where}) | Result |`);
  console.log("| --- | --- |");
  console.log(
    `| \`set\` | ${String(kept.write.ms)} ms on instance ${kept.write.instance} |`,
  );

  for (const read of kept.reads) {
    const met = read.instance === kept.write.instance ? "same" : "another";

    console.log(
      `| \`get\` on ${met} instance (${read.instance}) | ${read.found ? `found, written by ${read.writtenBy ?? "?"}` : "missing"}, ${String(read.ms)} ms |`,
    );
  }

  console.log(
    `| Entry from the last deployment | ${kept.version.previous === null ? "none" : kept.version.previous === kept.version.current ? "this deployment's" : `found, from ${kept.version.previous}`} |`,
  );

  const { set, hit, miss, samples } = kept.latency;

  console.log(
    `| Latency over ${String(samples)} round trips (p50 / p95) | set ${String(set.p50)} / ${String(set.p95)} ms, hit ${String(hit.p50)} / ${String(hit.p95)} ms, miss ${String(miss.p50)} / ${String(miss.p95)} ms |`,
  );
  console.log(
    `| ${String(kept.burst.calls)} \`expireTags\` calls in ${String(kept.burst.windowMs)} ms | ${String(kept.burst.accepted)} accepted in ${String(kept.burst.totalMs)} ms${kept.burst.errors.length > 0 ? `, rejects: ${kept.burst.errors.join("; ")}` : ""} |`,
  );
};

if (local) {
  const store: ProbeStore = memoryKeptStore();
  const write = await keptWrite(store);

  printKept("local, memoryKeptStore()", {
    write,
    reads: [await keptRead(store, write.key)],
    version: await versionRead(store, "local"),
    latency: await latency(store),
    burst: await burst(store),
  });
  exit(0);
}

if (!base || !secret) {
  console.error(
    "Usage: BSB_TAG_PROBE_SECRET=... node scripts/probe-vercel-tags.ts <preview-url> [--bypass <token>] [--second], or --local",
  );
  exit(2);
}

const headers = new Headers({ authorization: `Bearer ${secret}` });

if (bypass) {
  headers.set("x-vercel-protection-bypass", bypass);
}

const ask = (body: ProbeBody): Promise<Response> =>
  fetch(`${base}/api/probe/vercel-tags`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });

const response = await ask({ step: "tags" });

if (!response.ok) {
  console.error(
    `The probe answered ${String(response.status)}. A 404 means BSB_TAG_PROBE_SECRET is not set on the preview.`,
  );
  exit(1);
}

// SAFETY: the probe route answers this shape.
const answer = (await response.json()) as Answer;

const cell = (step: Step): string => {
  if (step.error !== null) {
    return `rejects: ${step.error}`;
  }

  if (step.goneAfter === null) {
    return "entry still there after 3 s";
  }

  return step.goneAtOnce
    ? "gone at once"
    : `gone after ${String(step.goneAfter)} ms`;
};

console.log("| Method | Stored | Runtime Cache entry after the call |");

console.log("| --- | --- | --- |");

for (const step of answer.steps) {
  console.log(
    `| \`${step.method}\` | ${step.stored ? "yes" : "no"} | ${cell(step)} |`,
  );
}

console.log("");

console.log("| Tags in one `expireTag` call | Result |");

console.log("| --- | --- |");

for (const { count, error } of answer.limits) {
  console.log(
    `| ${String(count)} | ${error === null ? "accepted" : `rejects: ${error}`} |`,
  );
}

console.log("");

console.log(
  `A tag over 256 bytes ${answer.oversizedTag.rejects ? `rejects the promise: ${answer.oversizedTag.error ?? ""}` : "resolves without an error"}.`,
);

// SAFETY: the probe route answers these shapes for each step.
const step = async <T>(body: ProbeBody): Promise<T> =>
  (await (await ask(body)).json()) as T;

const write = await step<KeptWrite>({ step: "kept-write" });
const reads: KeptRead[] = [];

for (let attempt = 0; attempt < (second ? 11 : 1); attempt += 1) {
  const read = await step<KeptRead>({ step: "kept-read", key: write.key });

  reads.push(read);

  if (read.instance !== write.instance) {
    break;
  }
}

printKept(base, {
  write,
  reads: reads.length > 1 ? [reads[0]!, reads.at(-1)!] : reads,
  version: await step<VersionRead>({ step: "version" }),
  latency: await step<Latency>({ step: "latency" }),
  burst: await step<Burst>({ step: "burst" }),
});
