import { expect, test } from "@playwright/test";

test("the complete fixture Board fits its reference viewport", async ({
  page,
}, testInfo) => {
  await page.goto("/board");

  const board = page.getByTestId("board");
  await expect(board).toBeVisible();
  await expect(page.getByRole("heading", { name: "Today" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Next" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Sideways" })).toBeVisible();

  const todayItems = page.locator('[data-board-item="today"]');
  const nextItems = page.locator('[data-board-item="next"]');
  await expect(todayItems).toHaveCount(3);
  await expect(nextItems).toHaveCount(2);
  expect(await todayItems.count()).toBeLessThanOrEqual(3);
  expect(await nextItems.count()).toBeLessThanOrEqual(2);

  const reasons = page.locator(".reason");
  await expect(reasons).toHaveCount(5);
  for (const reason of await reasons.all()) {
    await expect(reason).toBeVisible();
    await expect(reason).not.toHaveText("");
  }

  if (["ipad-webkit", "steam-deck-chromium"].includes(testInfo.project.name)) {
    await page.screenshot({
      path: testInfo.outputPath(`${testInfo.project.name}-board.png`),
      fullPage: true,
      animations: "disabled",
    });
  }

  const dimensions = await page.evaluate(() => {
    const boardElement = document.querySelector<HTMLElement>("[data-testid='board']");
    if (!boardElement) {
      throw new Error("Board element was not rendered");
    }

    const boardBounds = boardElement.getBoundingClientRect();
    return {
      boardTop: boardBounds.top,
      boardRight: boardBounds.right,
      boardBottom: boardBounds.bottom,
      boardLeft: boardBounds.left,
      viewportWidth: window.innerWidth,
      viewportHeight: window.innerHeight,
      documentWidth: Math.max(
        document.documentElement.scrollWidth,
        document.body.scrollWidth,
      ),
      documentHeight: Math.max(
        document.documentElement.scrollHeight,
        document.body.scrollHeight,
      ),
    };
  });

  expect(dimensions.boardTop).toBeGreaterThanOrEqual(0);
  expect(dimensions.boardLeft).toBeGreaterThanOrEqual(0);
  expect(dimensions.boardRight).toBeLessThanOrEqual(dimensions.viewportWidth + 1);
  expect(dimensions.boardBottom).toBeLessThanOrEqual(dimensions.viewportHeight + 1);
  expect(dimensions.documentWidth).toBeLessThanOrEqual(
    dimensions.viewportWidth + 1,
  );
  expect(dimensions.documentHeight).toBeLessThanOrEqual(
    dimensions.viewportHeight + 1,
  );
});
