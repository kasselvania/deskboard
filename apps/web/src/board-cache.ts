import {
  boardSnapshotSchema,
  type BoardSnapshot,
} from "@deskboard/contracts";

export const BOARD_CACHE_KEY = "deskboard.board.v1";

type ReadableBoardStorage = Pick<Storage, "getItem" | "removeItem">;
type WritableBoardStorage = Pick<Storage, "setItem">;

function discardCachedBoard(storage: ReadableBoardStorage): void {
  try {
    storage.removeItem(BOARD_CACHE_KEY);
  } catch {
    // Storage can be unavailable in a private or restricted browser context.
  }
}

export function readCachedBoard(
  storage: ReadableBoardStorage,
): BoardSnapshot | null {
  try {
    const serialized = storage.getItem(BOARD_CACHE_KEY);
    if (serialized === null) {
      return null;
    }

    const parsed = boardSnapshotSchema.safeParse(JSON.parse(serialized));
    if (!parsed.success) {
      discardCachedBoard(storage);
      return null;
    }

    return parsed.data;
  } catch {
    discardCachedBoard(storage);
    return null;
  }
}

export function writeCachedBoard(
  storage: WritableBoardStorage,
  board: BoardSnapshot,
): void {
  try {
    storage.setItem(BOARD_CACHE_KEY, JSON.stringify(board));
  } catch {
    // A storage quota or privacy mode must not prevent the live Board rendering.
  }
}
