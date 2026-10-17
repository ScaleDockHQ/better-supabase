import { expect, test } from "@playwright/test";
import { decodePreset } from "better-supabase/preset";

test("ticking comments switches on tenant and access, and the URL keeps the selection", async ({
  page,
}) => {
  await page.goto("/create?preset=minimal");

  const block = (name: string) =>
    page.locator(`input[name="block"][value="${name}"]`);

  await expect(block("comments")).not.toBeChecked();
  await expect(block("tenant")).not.toBeChecked();

  await block("comments").check();

  await expect(block("comments")).toBeChecked();

  for (const name of ["tenant", "access"]) {
    await expect(block(name)).toBeChecked();
    await expect(block(name)).toBeDisabled();
  }

  await expect(page.getByText("Required by comments").first()).toBeVisible();
  await expect(page).toHaveURL(/\/create\?preset=[1-9A-Z][0-9A-Za-z]+$/);
  const code = new URL(page.url()).searchParams.get("preset") ?? "";
  await expect(page.getByTestId("install-command")).toHaveText(
    `npx better-supabase init --preset ${code}`,
  );
  expect(decodePreset(code).preset.blocks.toSorted()).toEqual([
    "comments",
    "profiles",
  ]);

  // The code alone restores the same selection.
  await page.goto(`/create?preset=${code}`);
  await expect(block("comments")).toBeChecked();
  await expect(block("access")).toBeDisabled();
});
