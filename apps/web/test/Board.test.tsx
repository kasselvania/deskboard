// @vitest-environment jsdom

import { parseBoardSnapshot, type BoardSnapshot } from "@deskboard/contracts";
import { act, render, screen } from "@testing-library/react";
import axe from "axe-core";
import { afterEach, describe, expect, it, vi } from "vitest";

import defaultFixture from "../../../fixtures/board/default.json";
import emptyFixture from "../../../fixtures/board/empty.json";
import eventKitFixture from "../../../fixtures/board/eventkit-derived.json";
import staleFixture from "../../../fixtures/board/stale.json";
import { App } from "../src/App";
import { Board } from "../src/Board";
import { BOARD_CACHE_KEY, readCachedBoard } from "../src/board-cache";
import { BOARD_POLL_INTERVAL_MS } from "../src/use-board-snapshot";

const defaultBoard = parseBoardSnapshot(defaultFixture);
const emptyBoard = parseBoardSnapshot(emptyFixture);
const eventKitBoard = parseBoardSnapshot(eventKitFixture);
const staleBoard = parseBoardSnapshot(staleFixture);
const fixedNow = new Date("2026-08-21T17:05:00Z");
const savedAtText = new Intl.DateTimeFormat(undefined, {
  hour: "numeric",
  minute: "2-digit",
}).format(new Date(defaultBoard.generatedAt));

function renderBoard(snapshot: BoardSnapshot) {
  return render(
    <Board
      snapshot={snapshot}
      source="live"
      updateFailed={false}
      now={fixedNow}
    />,
  );
}

function successfulResponse(value: unknown = defaultFixture): Response {
  return new Response(JSON.stringify(value), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

afterEach(() => {
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

describe("Board rendering", () => {
  it("renders the default server-composed Board and every reason", () => {
    renderBoard(defaultBoard);

    expect(screen.getByRole("heading", { name: "Today" })).toBeVisible();
    expect(screen.getByRole("heading", { name: "Next" })).toBeVisible();
    expect(screen.getByRole("heading", { name: "Sideways" })).toBeVisible();
    expect(screen.getByText("Return the library book")).toBeVisible();
    expect(screen.getByText("due today")).toBeVisible();
    expect(screen.getByText("first commitment tomorrow")).toBeVisible();
    expect(screen.getByLabelText("Source freshness")).toHaveTextContent(
      "Reminders fixture · Calendar fixture",
    );
  });

  it("treats empty Today and Next regions as a calm success state", () => {
    renderBoard(emptyBoard);

    expect(screen.getByText("Nothing needs this space today.")).toBeVisible();
    expect(
      screen.getByText("No commitments are asking for attention."),
    ).toBeVisible();
    expect(screen.queryByRole("heading", { name: "Sideways" })).toBeNull();
  });

  it("represents stale sources with text rather than color alone", () => {
    renderBoard(staleBoard);

    expect(screen.getByLabelText("Source freshness")).toHaveTextContent(
      "Reminders delayed · Calendar delayed",
    );
    expect(screen.getByText("saved from the last source update")).toBeVisible();
  });

  it("renders the synthetic EventKit-derived fixture through the unchanged Board contract", () => {
    renderBoard(eventKitBoard);

    expect(screen.getByText("Synthetic Reminder A")).toBeVisible();
    expect(screen.getByText("Synthetic Reminder B")).toBeVisible();
    expect(screen.getByText("Synthetic Event A")).toBeVisible();
    expect(screen.getByText("Synthetic Event B")).toBeVisible();
    expect(screen.queryByRole("button")).toBeNull();
    expect(screen.queryByRole("link")).toBeNull();
  });

  it("has no automated accessibility violations in the default Board", async () => {
    const { container } = renderBoard(defaultBoard);
    const result = await axe.run(container, {
      rules: {
        "color-contrast": { enabled: false },
      },
    });

    expect(result.violations).toEqual([]);
  });
});

describe("Board data lifecycle", () => {
  it("treats restricted browser storage as an empty cache", () => {
    const restrictedStorage = {
      getItem: () => {
        throw new DOMException("Storage blocked", "SecurityError");
      },
      removeItem: () => {
        throw new DOMException("Storage blocked", "SecurityError");
      },
    };

    expect(readCachedBoard(restrictedStorage)).toBeNull();
  });

  it("shows a static loading state when there is no cache", () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(() => new Promise<Response>(() => undefined)),
    );

    render(<App />);

    expect(
      screen.getByRole("heading", { name: "Preparing the Board" }),
    ).toBeVisible();
    expect(screen.getByRole("status")).toHaveTextContent(
      "Looking for the latest fixture snapshot.",
    );
  });

  it("keeps a valid saved Board visible when the API fails", async () => {
    window.localStorage.setItem(BOARD_CACHE_KEY, JSON.stringify(defaultFixture));
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("offline")));

    render(<App />);

    expect(screen.getByText("Return the library book")).toBeVisible();
    expect(
      await screen.findByText(
        `Saved ${savedAtText} · live update unavailable · Reminders fixture · Calendar fixture`,
      ),
    ).toBeVisible();
  });

  it("timestamps a saved Board while checking for a live update", () => {
    window.localStorage.setItem(BOARD_CACHE_KEY, JSON.stringify(defaultFixture));
    vi.stubGlobal(
      "fetch",
      vi.fn(() => new Promise<Response>(() => undefined)),
    );

    render(<App />);

    expect(
      screen.getByText(
        `Saved ${savedAtText} · checking for an update · Reminders fixture · Calendar fixture`,
      ),
    ).toBeVisible();
  });

  it("shows a concise API error when no cache is available", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("offline")));

    render(<App />);

    expect(
      await screen.findByRole("heading", { name: "Board unavailable" }),
    ).toBeVisible();
    expect(screen.getByRole("alert")).not.toHaveTextContent(/offline|stack|fetch/i);
  });

  it("discards invalid cached data before handling an API failure", async () => {
    window.localStorage.setItem(
      BOARD_CACHE_KEY,
      JSON.stringify({ schemaVersion: 2, privateField: "not rendered" }),
    );
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new Error("offline")));

    render(<App />);

    expect(
      await screen.findByRole("heading", { name: "Board unavailable" }),
    ).toBeVisible();
    expect(window.localStorage.getItem(BOARD_CACHE_KEY)).toBeNull();
    expect(screen.queryByText("not rendered")).toBeNull();
  });

  it("rejects an unsupported response schema without caching it", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        successfulResponse({ ...defaultFixture, schemaVersion: 2 }),
      ),
    );

    render(<App />);

    expect(
      await screen.findByRole("heading", { name: "Board unavailable" }),
    ).toBeVisible();
    expect(window.localStorage.getItem(BOARD_CACHE_KEY)).toBeNull();
  });

  it("stores a valid live response and polls no more than once per minute", async () => {
    vi.useFakeTimers();
    const fetchMock = vi.fn().mockImplementation(async () => successfulResponse());
    vi.stubGlobal("fetch", fetchMock);

    render(<App />);
    await act(async () => {
      await Promise.resolve();
      await Promise.resolve();
    });

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(window.localStorage.getItem(BOARD_CACHE_KEY)).not.toBeNull();

    await act(async () => {
      await vi.advanceTimersByTimeAsync(BOARD_POLL_INTERVAL_MS - 1);
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);

    await act(async () => {
      await vi.advanceTimersByTimeAsync(1);
      await Promise.resolve();
      await Promise.resolve();
    });
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("suppresses polling while hidden and refreshes when visible again", async () => {
    vi.useFakeTimers();
    const visibility = vi
      .spyOn(document, "visibilityState", "get")
      .mockReturnValue("visible");
    const fetchMock = vi.fn().mockImplementation(async () => successfulResponse());
    vi.stubGlobal("fetch", fetchMock);

    render(<App />);
    await act(async () => {
      await Promise.resolve();
      await Promise.resolve();
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);

    visibility.mockReturnValue("hidden");
    act(() => {
      document.dispatchEvent(new Event("visibilitychange"));
    });
    await act(async () => {
      await vi.advanceTimersByTimeAsync(BOARD_POLL_INTERVAL_MS * 2);
    });
    expect(fetchMock).toHaveBeenCalledTimes(1);

    visibility.mockReturnValue("visible");
    await act(async () => {
      document.dispatchEvent(new Event("visibilitychange"));
      await Promise.resolve();
      await Promise.resolve();
    });
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });
});
