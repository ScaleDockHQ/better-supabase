"use server";

import { ok } from "better-supabase";
import { FORM_FIELD_TYPES } from "better-supabase/blocks/forms";
import * as v from "valibot";

import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/** A form key: lowercase letters, digits, `_` and `-`, unique per organization. */
function keyOf(title: string): string {
  const slug = title
    .toLowerCase()
    .replaceAll(/[^a-z0-9]+/g, "-")
    .replaceAll(/^-+|-+$/g, "")
    .slice(0, 40);

  return `${slug || "form"}-${crypto.randomUUID().slice(0, 8)}`;
}

export const createForm = bsb.action(
  {
    input: v.object({
      title: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
      description: v.optional(
        v.pipe(v.string(), v.trim(), v.maxLength(1000)),
        "",
      ),
    }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "forms.manage"),
  },
  async ({ title, description }, { tenant, db, auth }) => {
    const base = { organizationId: tenant, key: keyOf(title), title };

    const form = await db.forms.create(
      description === "" ? base : { ...base, description },
    );

    if (!form.ok) {
      return form;
    }

    await refreshCaller(auth);

    return ok({ id: form.data.id, title: form.data.title });
  },
);

const Field = v.object({
  key: v.pipe(v.string(), v.regex(/^[a-z][a-zA-Z0-9_]{0,62}$/)),
  label: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
  type: v.picklist(FORM_FIELD_TYPES),
  required: v.boolean(),
  options: v.optional(
    v.array(
      v.object({
        value: v.pipe(v.string(), v.minLength(1), v.maxLength(200)),
        label: v.pipe(v.string(), v.minLength(1), v.maxLength(200)),
      }),
    ),
  ),
});

/** Publishes the fields as the form's next version; a draft form opens. */
export const publishForm = bsb.action(
  {
    input: v.object({
      formId: Id,
      fields: v.pipe(v.array(Field), v.minLength(1), v.maxLength(50)),
    }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "forms.manage"),
  },
  async ({ formId, fields }, { db, auth }) => {
    const version = await db.forms.publish(formId, {
      steps: [
        {
          key: "main",
          fields: fields.map(({ options, ...field }) =>
            options === undefined ? field : { ...field, options },
          ),
        },
      ],
    });

    if (!version.ok) {
      return version;
    }

    await refreshCaller(auth);

    return ok({ number: version.data.number });
  },
);

const Answer = v.union([
  v.string(),
  v.number(),
  v.boolean(),
  v.array(v.string()),
]);

/** Postgres validates the answers against the current version's schema. */
export const submitForm = bsb.action(
  {
    input: v.object({ formId: Id, answers: v.record(v.string(), Answer) }),
    requireTenant: true,
    authorize: async () => can(await getPermissions(), "forms.submit"),
  },
  async ({ formId, answers }, { db, auth }) => {
    const submission = await db.forms.submit(formId, answers);

    if (!submission.ok) {
      return submission;
    }

    await refreshCaller(auth);

    return ok({ id: submission.data.id });
  },
);
