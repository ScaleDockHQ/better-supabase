/**
 * Every recipe route renders its recipe. The region is the element with
 * `data-recipe="<slug>"`, the one `recipe-screenshots.spec.ts` captures.
 */
import { expect, test } from "@playwright/test";

import { users } from "./users";

const ROUTES: readonly { readonly slug: string; readonly path: string }[] = [
  { slug: "profile-form", path: "/en/settings/profile" },
  { slug: "mfa-setup", path: "/en/settings/security" },
  { slug: "workspace-url-field", path: "/en/settings/organization" },
  { slug: "inbox-threads", path: "/en/inbox" },
  { slug: "ai-task-queue", path: "/en/assistant/tasks" },
  { slug: "ai-provider-settings", path: "/en/settings/ai-providers" },
  { slug: "chat-with-history", path: "/en/assistant" },
  { slug: "agent-run-trace", path: "/en/assistant/activity" },
  { slug: "knowledge-upload", path: "/en/knowledge" },
  { slug: "workflow-runs", path: "/en/workflows" },
];

test.use({ storageState: users.admin.storageState });

for (const route of ROUTES) {
  test(`${route.slug} renders on ${route.path}`, async ({ page }) => {
    await page.goto(route.path);

    await expect(
      page.locator(`[data-recipe="${route.slug}"]`).filter({ visible: true }),
    ).toBeVisible();
  });
}
