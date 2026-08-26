const [origin = "http://private-proxy:8080"] = process.argv.slice(2);
const { boardSnapshotSchema } = await import(
  "/app/packages/contracts/dist/index.js"
);

const healthResponse = await fetch(`${origin}/health`);
const health = await healthResponse.json();
if (
  !healthResponse.ok ||
  health.status !== "ok" ||
  health.service !== "deskboard-api"
) {
  throw new Error("Synthetic deployment health validation failed.");
}

const boardResponse = await fetch(`${origin}/v1/board`);
const board = boardSnapshotSchema.parse(await boardResponse.json());
if (
  !boardResponse.ok ||
  boardResponse.headers.get("cache-control") !== "no-store"
) {
  throw new Error("Synthetic deployed Board validation failed.");
}

process.stdout.write(
  JSON.stringify({
    schemaValid: true,
    todayCount: board.today.items.length,
    nextCount: board.next.items.length,
    calendarFreshness: board.freshness.calendar.status,
    remindersFreshness: board.freshness.reminders.status,
  }) + "\n",
);
