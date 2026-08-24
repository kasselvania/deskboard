import { buildApp } from "./app.js";
import { readDeskboardRuntimeConfiguration } from "./board-configuration.js";
import type { ContentFreeBoardAcceptanceSummary } from "./mirror-backed-board/index.js";

type FailedContentFreeBoardAcceptanceSummary = Omit<
  ContentFreeBoardAcceptanceSummary,
  "schemaValid"
> & { schemaValid: false };

const failedSummary: FailedContentFreeBoardAcceptanceSummary = {
  schemaValid: false,
  todayItemCount: 0,
  nextItemCount: 0,
  calendarFreshness: "unavailable",
  remindersFreshness: "unavailable",
  selectedSourceCounts: { calendar: 0, reminders: 0 },
  sources: [],
};

async function main(): Promise<void> {
  let app: ReturnType<typeof buildApp> | undefined;
  try {
    const runtime = readDeskboardRuntimeConfiguration(process.env);
    if (
      runtime.board.mode !== "apple-mirror" ||
      !runtime.appleSourceIngestion
    ) {
      throw new Error();
    }
    let summary: ContentFreeBoardAcceptanceSummary | undefined;
    app = buildApp({
      board: runtime.board,
      appleSourceIngestion: runtime.appleSourceIngestion,
      contentFreeBoardObserver: (value) => {
        summary = value;
      },
    });
    const response = await app.inject({
      method: "GET",
      url: "/v1/board",
    });
    if (response.statusCode !== 200 || !summary) {
      throw new Error();
    }
    process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
  } catch {
    process.stdout.write(`${JSON.stringify(failedSummary, null, 2)}\n`);
    process.exitCode = 1;
  } finally {
    await app?.close();
  }
}

await main();
