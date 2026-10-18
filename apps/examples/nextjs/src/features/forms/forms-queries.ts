import "server-only";
import type {
  FormField,
  FormStatus,
  FormSubmission,
  FormSubmissionStatus,
} from "better-supabase/blocks/forms";

import { tenantOf } from "better-supabase/next";
import { notFound, unstable_rethrow } from "next/navigation";
import * as v from "valibot";

import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

const UUID = /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i;

export interface FormSummary {
  readonly id: string;
  readonly title: string;
  readonly description: string | null;
  readonly status: FormStatus;
  /** ISO 8601, so the cached value stays serializable. */
  readonly createdAt: string;
}

/** An answer as the responses table shows it. */
export type AnswerCell =
  | { readonly kind: "text"; readonly text: string }
  | { readonly kind: "bool"; readonly value: boolean };

const AnswerCell = v.union([
  v.pipe(
    v.boolean(),
    v.transform((value): AnswerCell => ({ kind: "bool", value })),
  ),
  v.pipe(
    v.array(v.string()),
    v.transform((items): AnswerCell => ({
      kind: "text",
      text: items.join(", "),
    })),
  ),
  v.pipe(
    v.union([v.string(), v.number()]),
    v.transform((value): AnswerCell => ({ kind: "text", text: String(value) })),
  ),
]);

export interface FormSubmissionRow {
  readonly id: string;
  readonly status: FormSubmissionStatus;
  /** Answers the current fields can't show are left out. */
  readonly answers: Readonly<Record<string, AnswerCell>>;
  readonly createdAt: string;
}

export interface FormDetailView {
  readonly form: FormSummary;
  readonly version: number | null;
  /** Every field of the current version, in step order. */
  readonly fields: readonly FormField[];
  readonly submissions: readonly FormSubmissionRow[];
}

export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

/** A failed read throws, so it is never cached and Retry reads again. */
async function loadForms(): Promise<readonly FormSummary[] | null> {
  "use cache: private";
  const { session, supabase } = await bs.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const forms = await blocks(supabase).forms.list(tenant).orThrow();

  return forms.map((form) => ({
    id: form.id,
    title: form.title,
    description: form.description ?? null,
    status: form.status,
    createdAt: form.createdAt.toString(),
  }));
}

export async function getForms(): Promise<Loaded<readonly FormSummary[]>> {
  try {
    const forms = await loadForms();

    return forms === null
      ? { kind: "no-organization" }
      : { kind: "ok", data: forms };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

function answerCells(answers: FormSubmission["answers"]) {
  return Object.fromEntries(
    Object.entries(answers).flatMap(([key, answer]) => {
      const parsed = v.safeParse(AnswerCell, answer);

      return parsed.success ? [[key, parsed.output] as const] : [];
    }),
  );
}

async function loadForm(id: string): Promise<FormDetailView | "not-found"> {
  "use cache: private";
  const { supabase } = await bs.cached();
  const { forms } = blocks(supabase);

  const [detail, submissions] = await Promise.all([
    forms.get(id),
    forms.listSubmissions(id, { pageSize: 100 }),
  ]);

  if (!detail.ok) {
    if (detail.error.kind === "not_found") {
      return "not-found";
    }

    throw new Error(detail.error.message);
  }

  if (!submissions.ok) {
    throw new Error(submissions.error.message);
  }

  const form = detail.data;

  return {
    form: {
      id: form.id,
      title: form.title,
      description: form.description ?? null,
      status: form.status,
      createdAt: form.createdAt.toString(),
    },
    version: form.version?.number ?? null,
    fields: form.version?.definition.steps.flatMap((step) => step.fields) ?? [],
    submissions: submissions.data.map((submission) => ({
      id: submission.id,
      status: submission.status,
      answers: answerCells(submission.answers),
      createdAt: (submission.submittedAt ?? submission.createdAt).toString(),
    })),
  };
}

export async function getForm(id: string): Promise<Loaded<FormDetailView>> {
  if (!UUID.test(id)) {
    notFound();
  }

  let form: FormDetailView | "not-found";

  try {
    form = await loadForm(id);
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }

  if (form === "not-found") {
    notFound();
  }

  return { kind: "ok", data: form };
}
