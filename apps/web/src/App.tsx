import { Board } from "./Board";
import { useBoardSnapshot } from "./use-board-snapshot";

function BoardState({
  title,
  detail,
  isError = false,
}: {
  title: string;
  detail: string;
  isError?: boolean;
}) {
  return (
    <main className="board-shell state-shell">
      <header className="state-header">
        <p className="wordmark">Deskboard</p>
        <h1>{title}</h1>
      </header>
      <p className="state-detail" role={isError ? "alert" : "status"}>
        {detail}
      </p>
    </main>
  );
}

export function App() {
  const boardState = useBoardSnapshot();

  if (boardState.status === "loading") {
    return (
      <BoardState
        title="Preparing the Board"
        detail="Looking for the latest fixture snapshot."
      />
    );
  }

  if (boardState.status === "error") {
    return (
      <BoardState
        title="Board unavailable"
        detail="Deskboard could not reach the Board. It will try again when this page is visible."
        isError
      />
    );
  }

  return (
    <Board
      snapshot={boardState.snapshot}
      source={boardState.source}
      updateFailed={boardState.updateFailed}
    />
  );
}
