import type { FieldValue } from "better-supabase/blocks/custom-fields";

import { tenantOf } from "better-supabase/next";
import { getExtracted } from "next-intl/server";
import * as v from "valibot";

import { Badge } from "@/components/reui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";
import { bsb } from "@/lib/supabase/server";

import type { RecordSubject } from "../record-subject";

import { recordPages } from "../record-pages";
import { RecordLoadError } from "./record-card-states";

/** The tags on a record, as chips. Renders nothing without `tags.read`. */
// skeleton: its parent page or section renders it inside a Suspense with a fallback of the same shape.
export async function RecordTags({ subject }: { subject: RecordSubject }) {
  const [t, permissions] = await Promise.all([
    getExtracted("records"),
    getPermissions(),
  ]);

  if (!can(permissions, "tags.read")) {
    return null;
  }

  const { bindings } = await recordPages[subject.type].get(subject.id, {
    bindings: ["tags"],
  });

  const loaded = bindings.tags;

  if (loaded.kind === "hidden") {
    return null;
  }

  if (loaded.kind === "error") {
    return <RecordLoadError title={t("The tags didn't load")} />;
  }

  return (
    <Card size="sm" id="tags">
      <CardHeader>
        <CardTitle>{t("Tags")}</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-wrap items-center gap-1">
        {loaded.data.length === 0 ? (
          <p className="text-sm text-muted-foreground">{t("No tags yet.")}</p>
        ) : (
          loaded.data.map((tag) => (
            <Badge key={tag.id} variant="secondary">
              {tag.name}
            </Badge>
          ))
        )}
      </CardContent>
    </Card>
  );
}

const Scalar = v.union([v.string(), v.number(), v.boolean()]);

const display = (field: FieldValue): string => {
  const parsed = v.safeParse(Scalar, field.value);

  return parsed.success ? String(parsed.output) : "–";
};

/**
 * The custom field values of a record. Renders nothing without
 * `custom-fields.read`.
 */
// skeleton: its parent page or section renders it inside a Suspense with a fallback of the same shape.
export async function RecordFields({ subject }: { subject: RecordSubject }) {
  const [t, permissions] = await Promise.all([
    getExtracted("records"),
    getPermissions(),
  ]);

  if (!can(permissions, "custom_fields.read")) {
    return null;
  }

  const { bindings } = await recordPages[subject.type].get(subject.id, {
    bindings: ["customFields"],
  });

  const loaded = bindings.customFields;

  if (loaded.kind === "hidden") {
    return null;
  }

  if (loaded.kind === "error") {
    return <RecordLoadError title={t("The custom fields didn't load")} />;
  }

  return (
    <Card size="sm" id="fields">
      <CardHeader>
        <CardTitle>{t("Custom fields")}</CardTitle>
        <CardDescription>
          {t("Defined in the organization's settings.")}
        </CardDescription>
      </CardHeader>
      <CardContent>
        {loaded.data.length === 0 ? (
          <p className="text-sm text-muted-foreground">{t("No values set.")}</p>
        ) : (
          <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-sm">
            {loaded.data.map((field) => (
              <div key={field.id} className="contents">
                <dt className="text-muted-foreground">{field.label}</dt>
                <dd className="min-w-0 truncate text-right font-medium">
                  {display(field)}
                </dd>
              </div>
            ))}
          </dl>
        )}
      </CardContent>
    </Card>
  );
}

/**
 * The approval requests filed on a record. Renders nothing without
 * `approvals.read`.
 */
// skeleton: its parent page or section renders it inside a Suspense with a fallback of the same shape.
export async function RecordApprovals({ subject }: { subject: RecordSubject }) {
  const [t, permissions, { db }, session] = await Promise.all([
    getExtracted("records"),
    getPermissions(),
    bsb.context(),
    getSession(),
  ]);

  const tenant = tenantOf(session);

  if (!tenant || !can(permissions, "approvals.read")) {
    return null;
  }

  const page = await db.approvals.page({
    limit: 10,
    filters: { subjectType: [subject.type], subjectId: [subject.id] },
  });

  if (!page.ok) {
    return <RecordLoadError title={t("The approvals didn't load")} />;
  }

  return (
    <Card size="sm" id="approvals">
      <CardHeader>
        <CardTitle>{t("Approvals")}</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-2">
        {page.data.items.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            {t("Nothing waits for approval.")}
          </p>
        ) : (
          page.data.items.map((request) => (
            <div
              key={request.id}
              className="flex items-center justify-between gap-2 text-sm"
            >
              <span className="truncate">{request.action}</span>
              <Badge variant="outline">{request.status}</Badge>
            </div>
          ))
        )}
      </CardContent>
    </Card>
  );
}

/** The caller's reminders on a record. Renders nothing without `reminders.read`. */
// skeleton: its parent page or section renders it inside a Suspense with a fallback of the same shape.
export async function RecordReminders({ subject }: { subject: RecordSubject }) {
  const [t, permissions, { db }, session] = await Promise.all([
    getExtracted("records"),
    getPermissions(),
    bsb.context(),
    getSession(),
  ]);

  const tenant = tenantOf(session);

  if (!tenant || !can(permissions, "reminders.read")) {
    return null;
  }

  const page = await db.reminders.page({
    organizationId: tenant,
    limit: 10,
    filters: { subjectType: [subject.type], subjectId: [subject.id] },
  });

  if (!page.ok) {
    return <RecordLoadError title={t("The reminders didn't load")} />;
  }

  return (
    <Card size="sm" id="reminders">
      <CardHeader>
        <CardTitle>{t("Reminders")}</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-2">
        {page.data.items.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            {t("You set no reminder on this record.")}
          </p>
        ) : (
          page.data.items.map((reminder) => (
            <div
              key={reminder.id}
              className="flex items-center justify-between gap-2 text-sm"
            >
              <span>{reminder.method}</span>
              <span className="text-muted-foreground">
                {t("{minutes} min before", {
                  minutes: String(reminder.offsetMinutes),
                })}
              </span>
            </div>
          ))
        )}
      </CardContent>
    </Card>
  );
}
