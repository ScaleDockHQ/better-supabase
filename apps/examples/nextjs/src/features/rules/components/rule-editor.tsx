import { tenantOf } from "better-supabase/next";
import { forbidden, notFound } from "next/navigation";

import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { RuleBuilder } from "./rule-builder";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Render inside `<Suspense>`: reads the `rule` param, `new` for a new rule. */
export async function RuleEditor({
  params,
}: {
  params: Promise<{ rule: string }>;
}) {
  const [{ rule }, session, permissions] = await Promise.all([
    params,
    getSession(),
    getPermissions(),
  ]);

  const tenant = tenantOf(session);

  if (rule !== "new" && !UUID.test(rule)) {
    notFound();
  }

  if (!tenant || !can(permissions, "automations.read")) {
    forbidden();
  }

  const canEdit = can(permissions, "automations.write");

  if (rule === "new" && !canEdit) {
    forbidden();
  }

  return (
    <RuleBuilder
      key={rule}
      organizationId={tenant}
      rule={rule === "new" ? null : rule}
      canEdit={canEdit}
      canPublish={can(permissions, "automations.publish")}
    />
  );
}
