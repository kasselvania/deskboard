import {
  boardSnapshotSchema,
  type BoardSnapshot,
} from "@deskboard/contracts";
import { useEffect, useState } from "react";

import { readCachedBoard, writeCachedBoard } from "./board-cache";

export const BOARD_POLL_INTERVAL_MS = 60_000;

export type BoardLoadState =
  | { status: "loading" }
  | {
      status: "ready";
      snapshot: BoardSnapshot;
      source: "live" | "saved";
      updateFailed: boolean;
    }
  | { status: "error" };

function getStorage(): Storage | null {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

function getInitialState(): BoardLoadState {
  const storage = getStorage();
  const cached = storage ? readCachedBoard(storage) : null;

  if (cached) {
    return {
      status: "ready",
      snapshot: cached,
      source: "saved",
      updateFailed: false,
    };
  }

  return { status: "loading" };
}

export function useBoardSnapshot(): BoardLoadState {
  const [state, setState] = useState<BoardLoadState>(getInitialState);

  useEffect(() => {
    let disposed = false;
    let requestInFlight = false;
    let controller: AbortController | null = null;
    let pollTimer: number | null = null;

    async function refresh(): Promise<void> {
      if (requestInFlight) {
        return;
      }

      requestInFlight = true;
      controller = new AbortController();

      try {
        const response = await fetch("/v1/board", {
          headers: { Accept: "application/json" },
          signal: controller.signal,
        });

        if (!response.ok) {
          throw new Error("Board request failed");
        }

        const parsed = boardSnapshotSchema.safeParse(await response.json());
        if (!parsed.success) {
          throw new Error("Board response did not match schema version 1");
        }

        if (disposed) {
          return;
        }

        const storage = getStorage();
        if (storage) {
          writeCachedBoard(storage, parsed.data);
        }

        setState({
          status: "ready",
          snapshot: parsed.data,
          source: "live",
          updateFailed: false,
        });
      } catch (error) {
        if (disposed || (error instanceof DOMException && error.name === "AbortError")) {
          return;
        }

        setState((current) => {
          if (current.status === "ready") {
            return {
              ...current,
              source: "saved",
              updateFailed: true,
            };
          }

          return { status: "error" };
        });
      } finally {
        requestInFlight = false;
        controller = null;
      }
    }

    function stopPolling(): void {
      if (pollTimer !== null) {
        window.clearInterval(pollTimer);
        pollTimer = null;
      }
    }

    function startPolling(): void {
      stopPolling();
      if (document.visibilityState === "hidden") {
        return;
      }

      pollTimer = window.setInterval(() => {
        if (document.visibilityState === "visible") {
          void refresh();
        }
      }, BOARD_POLL_INTERVAL_MS);
    }

    function handleVisibilityChange(): void {
      if (document.visibilityState === "visible") {
        void refresh();
        startPolling();
      } else {
        stopPolling();
      }
    }

    void refresh();
    startPolling();
    document.addEventListener("visibilitychange", handleVisibilityChange);

    return () => {
      disposed = true;
      controller?.abort();
      stopPolling();
      document.removeEventListener("visibilitychange", handleVisibilityChange);
    };
  }, []);

  return state;
}
