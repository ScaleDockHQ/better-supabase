import type { Locator, Page } from "@playwright/test";

import { expect, test } from "@playwright/test";

import { users } from "./users";

/**
 * Waits for the recipe to show its rows or its empty state, and returns its
 * card.
 */
async function loadedRecipe(
  page: Page,
  recipe: string,
  testIds: readonly [rows: string, empty: string],
): Promise<Locator> {
  // Streamed Suspense content sits in a hidden copy until React swaps it in.
  const card = page
    .locator(`[data-recipe="${recipe}"]`)
    .filter({ visible: true });

  await card
    .getByTestId(testIds[0])
    .or(card.getByTestId(testIds[1]))
    .first()
    .waitFor({ state: "visible" });

  return card;
}

/** A read that failed renders an inline error with this button. */
const retry = (card: Locator): Locator =>
  card.getByRole("button", { name: "Retry" });

test.describe("admin", () => {
  test.use({ storageState: users.admin.storageState });

  test("the AI task queue lists the tasks or offers to schedule one", async ({
    page,
  }) => {
    await page.goto("/en/assistant/tasks");

    const card = await loadedRecipe(page, "ai-task-queue", [
      "ai-schedules",
      "ai-tasks-empty",
    ]);

    await expect(retry(card)).toHaveCount(0);
  });

  test("the AI provider settings list the keys or offer to add one", async ({
    page,
  }) => {
    await page.goto("/en/settings/ai-providers");

    const card = await loadedRecipe(page, "ai-provider-settings", [
      "ai-provider-keys",
      "ai-providers-empty",
    ]);

    await expect(retry(card)).toHaveCount(0);
  });
});

test.describe("member", () => {
  test.use({ storageState: users.member.storageState });

  test("sees their own AI tasks", async ({ page }) => {
    await page.goto("/en/assistant/tasks");

    const card = await loadedRecipe(page, "ai-task-queue", [
      "ai-schedules",
      "ai-tasks-empty",
    ]);

    await expect(retry(card)).toHaveCount(0);
  });

  test("the AI provider settings need ai.admin", async ({ page }) => {
    await page.goto("/en/settings/ai-providers");
    await expect(page).toHaveURL((url) => url.pathname === "/en");
  });
});
