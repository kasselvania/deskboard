import type {
  BoardSnapshot,
  CommitmentItem,
  SourceFreshness,
  TaskItem,
} from "@deskboard/contracts";
import { useEffect, useState } from "react";

export interface BoardProps {
  snapshot: BoardSnapshot;
  source: "live" | "saved";
  updateFailed: boolean;
  now?: Date;
}

function useCurrentTime(fixedTime?: Date): Date {
  const [currentTime, setCurrentTime] = useState(() => fixedTime ?? new Date());

  useEffect(() => {
    if (fixedTime) {
      return;
    }

    const timer = window.setInterval(() => {
      setCurrentTime(new Date());
    }, 60_000);

    return () => {
      window.clearInterval(timer);
    };
  }, [fixedTime]);

  return fixedTime ?? currentTime;
}

function describeFreshness(freshness: SourceFreshness): string {
  switch (freshness.status) {
    case "fixture":
      return "fixture";
    case "fresh":
      return "current";
    case "stale":
      return "delayed";
    case "unavailable":
      return "unavailable";
  }
}

function getFreshnessText(
  snapshot: BoardSnapshot,
  source: BoardProps["source"],
  updateFailed: boolean,
): string {
  const delivery =
    source === "live"
      ? null
      : updateFailed
        ? "Saved board · live update unavailable"
        : "Saved board · checking for an update";
  const sourceStates = [
    `Reminders ${describeFreshness(snapshot.freshness.reminders)}`,
    `Calendar ${describeFreshness(snapshot.freshness.calendar)}`,
  ];

  return [delivery, ...sourceStates].filter(Boolean).join(" · ");
}

function BoardHeader({ now }: { now: Date }) {
  const dateText = new Intl.DateTimeFormat(undefined, {
    weekday: "long",
    month: "long",
    day: "numeric",
  }).format(now);
  const timeText = new Intl.DateTimeFormat(undefined, {
    hour: "numeric",
    minute: "2-digit",
  }).format(now);

  return (
    <header className="board-header">
      <div>
        <p className="wordmark">Deskboard</p>
        <h1>{dateText}</h1>
      </div>
      <time dateTime={now.toISOString()}>{timeText}</time>
    </header>
  );
}

function TaskRow({ item }: { item: TaskItem }) {
  return (
    <li className="attention-item" data-board-item="today">
      <div className="item-heading">
        <p className="item-title">{item.title}</p>
        {item.whenLabel ? <p className="when-label">{item.whenLabel}</p> : null}
      </div>
      <p className="reason">{item.reason}</p>
    </li>
  );
}

function CommitmentRow({ item }: { item: CommitmentItem }) {
  return (
    <li className="attention-item" data-board-item="next">
      <p className="when-label">{item.whenLabel}</p>
      <p className="item-title">{item.title}</p>
      <p className="reason">{item.reason}</p>
    </li>
  );
}

export function Board({
  snapshot,
  source,
  updateFailed,
  now,
}: BoardProps) {
  const currentTime = useCurrentTime(now);

  return (
    <main className="board-shell" data-testid="board">
      <BoardHeader now={currentTime} />
      <p className="freshness" role="status" aria-label="Source freshness">
        {getFreshnessText(snapshot, source, updateFailed)}
      </p>

      <div className="board-content">
        <section
          className="board-section board-section-today"
          aria-labelledby="today-heading"
        >
          <h2 id="today-heading">{snapshot.today.label}</h2>
          {snapshot.today.items.length > 0 ? (
            <ol className="attention-list">
              {snapshot.today.items.map((item) => (
                <TaskRow key={item.id} item={item} />
              ))}
            </ol>
          ) : (
            <p className="empty-state">Nothing needs this space today.</p>
          )}
        </section>

        <section
          className="board-section board-section-next"
          aria-labelledby="next-heading"
        >
          <h2 id="next-heading">{snapshot.next.label}</h2>
          {snapshot.next.items.length > 0 ? (
            <ol className="attention-list">
              {snapshot.next.items.map((item) => (
                <CommitmentRow key={item.id} item={item} />
              ))}
            </ol>
          ) : (
            <p className="empty-state">No commitments are asking for attention.</p>
          )}
        </section>

        {snapshot.sidewaysPrompt ? (
          <section
            className="board-section board-section-sideways"
            aria-labelledby="sideways-heading"
          >
            <h2 id="sideways-heading">{snapshot.sidewaysPrompt.label}</h2>
            <blockquote>{snapshot.sidewaysPrompt.text}</blockquote>
          </section>
        ) : null}
      </div>
    </main>
  );
}
