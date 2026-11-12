"use server";

import { ok } from "better-supabase";
import { createEvalJob, exactMatch } from "better-supabase/blocks/ai-evals";
import { refresh } from "next/cache";
import { after } from "next/server";
import * as v from "valibot";

import { promptsBlock } from "@/features/prompts/prompts-server";
import { bsbCore } from "@/lib/supabase/server-core";

import { evalsBlock } from "./evals-server";
import { answerFor } from "./evals-task";

const Name = v.pipe(v.string(), v.regex(/^[a-z0-9][a-z0-9._-]{2,79}$/));

/** The most a run works for, so the background job ends inside a function. */
const BUDGET_MS = 25_000;

/**
 * Adds items from lines of `input => expected`, so a dataset takes shape from a
 * paste.
 */
export const addEvalItems = bsbCore.action(
  {
    input: v.object({
      name: Name,
      lines: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(20_000)),
    }),
    requireTenant: true,
    permission: "ai_chat.manage",
  },
  async ({ name, lines }, { tenant }) => {
    const evals = evalsBlock();

    const dataset = await evals.datasets.create({
      name,
      organizationId: tenant,
    });

    if (!dataset.ok) {
      return dataset;
    }

    const items = lines
      .split("\n")
      .map((line) => line.split("=>"))
      .flatMap(([input, expected]) =>
        input === undefined || input.trim() === ""
          ? []
          : [{ input: input.trim(), expected: expected?.trim() }],
      );

    const added = await evals.items.add({
      datasetId: dataset.data.id,
      items: items.map((item) => ({
        input: item.input,
        ...(item.expected === undefined ? {} : { expected: item.expected }),
      })),
    });

    if (!added.ok) {
      return added;
    }

    refresh();

    return ok(added.data);
  },
);

/** Copies the answers users rated down in the assistant into the dataset. */
export const addEvalItemsFromFeedback = bsbCore.action(
  {
    input: v.object({ name: Name }),
    requireTenant: true,
    permission: "ai_chat.manage",
  },
  async ({ name }, { tenant }) => {
    const evals = evalsBlock();

    const dataset = await evals.datasets.create({
      name,
      organizationId: tenant,
    });

    if (!dataset.ok) {
      return dataset;
    }

    const added = await evals.items.addFromFeedback({
      datasetId: dataset.data.id,
      rating: -1,
    });

    if (!added.ok) {
      return added;
    }

    refresh();

    return ok(added.data);
  },
);

/**
 * Starts a run of the dataset against a prompt version and a model. The items
 * are answered and scored in the background; the page shows the run as it fills
 * in.
 */
export const startEvalRun = bsbCore.action(
  {
    input: v.object({
      name: Name,
      promptVersion: v.pipe(v.number(), v.integer(), v.minValue(1)),
      model: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(120)),
    }),
    requireTenant: true,
    permission: "ai_chat.manage",
  },
  async ({ name, promptVersion, model }, { tenant }) => {
    const evals = evalsBlock();

    const dataset = await evals.datasets.create({
      name,
      organizationId: tenant,
    });

    if (!dataset.ok) {
      return dataset;
    }

    const scorer = exactMatch();

    const run = await evals.runs.create({
      datasetId: dataset.data.id,
      promptName: name,
      promptVersion,
      model,
      scorers: [scorer],
    });

    if (!run.ok) {
      return run;
    }

    const job = createEvalJob({
      evals,
      scorers: [scorer],
      budgetMs: BUDGET_MS,
      concurrency: 4,
      task: async (item, started) => {
        const prompt = await promptsBlock()
          .get({ name, version: started.promptVersion, organizationId: tenant })
          .orThrow();

        if (prompt === undefined) {
          throw new TypeError(
            `Prompt ${name} v${started.promptVersion} is gone`,
          );
        }

        return answerFor({
          template: prompt.template,
          model: started.model,
          item,
          version: started.promptVersion,
        });
      },
    });

    after(async () => {
      await job({ runId: run.data.id });
    });

    refresh();

    return ok(run.data.id);
  },
);
