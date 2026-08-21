import { readFileSync } from "node:fs";

import { expect, test, type Page } from "@playwright/test";

import {
  BOARD_TEXT_LIMITS,
  parseBoardSnapshot,
  type BoardSnapshot,
} from "../../packages/contracts/src/index";

const defaultFixture = JSON.parse(
  readFileSync(
    new URL("../../fixtures/board/default.json", import.meta.url),
    "utf8",
  ),
) as unknown;

function maximumText(seed: string, length: number): string {
  const words = `${seed.trim()} `;
  const repeated = words.repeat(Math.ceil(length / words.length) + 1);
  const candidate = repeated.slice(0, length);
  return candidate.endsWith(" ")
    ? `${candidate.slice(0, -1)}.`
    : candidate;
}

function maximumId(prefix: string): string {
  return `${prefix}${"x".repeat(BOARD_TEXT_LIMITS.id - prefix.length)}`;
}

function maximumContentBoard(): BoardSnapshot {
  const board = structuredClone(parseBoardSnapshot(defaultFixture));

  board.boardVersion = maximumText(
    "maximum fixture version",
    BOARD_TEXT_LIMITS.boardVersion,
  );
  board.today.items.forEach((item, index) => {
    item.id = maximumId(`today-${index}-`);
    item.title = maximumText(
      "A maximum length fixture title stays calm and legible",
      BOARD_TEXT_LIMITS.title,
    );
    item.reason = maximumText(
      "Shown because a bounded reason should remain readable without clipping meaningful words",
      BOARD_TEXT_LIMITS.reason,
    );
    if (item.whenLabel) {
      item.whenLabel = maximumText(
        "Today before a quiet fixture moment",
        BOARD_TEXT_LIMITS.whenLabel,
      );
    }
  });
  board.next.items.forEach((item, index) => {
    item.id = maximumId(`next-${index}-`);
    item.title = maximumText(
      "A maximum length fixture commitment stays calm and legible",
      BOARD_TEXT_LIMITS.title,
    );
    item.reason = maximumText(
      "Shown because a bounded reason should remain readable without clipping meaningful words",
      BOARD_TEXT_LIMITS.reason,
    );
    item.whenLabel = maximumText(
      "Tomorrow at the fictional workshop",
      BOARD_TEXT_LIMITS.whenLabel,
    );
  });
  if (board.sidewaysPrompt) {
    board.sidewaysPrompt.text = maximumText(
      "Try the quieter edge of this fixture and notice what becomes easier to read before adding another demand",
      BOARD_TEXT_LIMITS.sidewaysPrompt,
    );
  }

  return parseBoardSnapshot(board);
}

async function boardDimensions(page: Page) {
  return page.evaluate(() => {
    const boardElement = document.querySelector<HTMLElement>(
      "[data-testid='board']",
    );
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
}

function expectBoardToFit(
  dimensions: Awaited<ReturnType<typeof boardDimensions>>,
) {
  expect(dimensions.boardTop).toBeGreaterThanOrEqual(0);
  expect(dimensions.boardLeft).toBeGreaterThanOrEqual(0);
  expect(dimensions.boardRight).toBeLessThanOrEqual(dimensions.viewportWidth + 1);
  expect(dimensions.boardBottom).toBeLessThanOrEqual(
    dimensions.viewportHeight + 1,
  );
  expect(dimensions.documentWidth).toBeLessThanOrEqual(
    dimensions.viewportWidth + 1,
  );
  expect(dimensions.documentHeight).toBeLessThanOrEqual(
    dimensions.viewportHeight + 1,
  );
}

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

  expectBoardToFit(await boardDimensions(page));
});

test("maximum valid display text fits the primary viewports", async (
  { page },
  testInfo,
) => {
  test.skip(
    testInfo.project.name === "portrait-chromium",
    "The maximum-content proof targets the two primary reference viewports.",
  );

  const maximumBoard = maximumContentBoard();
  expect(maximumBoard.boardVersion).toHaveLength(
    BOARD_TEXT_LIMITS.boardVersion,
  );
  expect(
    maximumBoard.today.items.every(
      (item) =>
        item.id.length === BOARD_TEXT_LIMITS.id &&
        item.title.length === BOARD_TEXT_LIMITS.title &&
        item.reason.length === BOARD_TEXT_LIMITS.reason &&
        (!item.whenLabel ||
          item.whenLabel.length === BOARD_TEXT_LIMITS.whenLabel),
    ),
  ).toBe(true);
  expect(
    maximumBoard.next.items.every(
      (item) =>
        item.id.length === BOARD_TEXT_LIMITS.id &&
        item.title.length === BOARD_TEXT_LIMITS.title &&
        item.reason.length === BOARD_TEXT_LIMITS.reason &&
        item.whenLabel.length === BOARD_TEXT_LIMITS.whenLabel,
    ),
  ).toBe(true);
  expect(maximumBoard.sidewaysPrompt!.text).toHaveLength(
    BOARD_TEXT_LIMITS.sidewaysPrompt,
  );
  await page.route("**/v1/board", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      headers: { "Cache-Control": "no-store" },
      body: JSON.stringify(maximumBoard),
    });
  });
  await page.goto("/board");

  await expect(page.locator(".item-title")).toHaveCount(5);
  await expect(page.locator(".reason")).toHaveCount(5);
  await expect(page.locator(".when-label")).toHaveCount(4);
  await expect(page.locator(".board-section-sideways blockquote")).toHaveText(
    maximumBoard.sidewaysPrompt!.text,
  );

  const textBoxes = await page
    .locator(
      ".item-title, .reason, .when-label, .board-section-sideways blockquote",
    )
    .evaluateAll((elements) =>
      elements.map((element) => ({
        text: element.textContent,
        widthFits: element.scrollWidth <= element.clientWidth + 1,
        heightFits: element.scrollHeight <= element.clientHeight + 1,
      })),
    );
  expect(
    textBoxes.every(({ widthFits, heightFits }) => widthFits && heightFits),
  ).toBe(true);
  expectBoardToFit(await boardDimensions(page));
});
