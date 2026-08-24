const { buildApp } = await import("/app/apps/api/dist/app.js");
const { boardSnapshotSchema } = await import(
  "/app/packages/contracts/dist/index.js"
);

const app = buildApp();
try {
  const boardResponse = await app.inject({ method: "GET", url: "/v1/board" });
  boardSnapshotSchema.parse(boardResponse.json());
  if (
    boardResponse.statusCode !== 200 ||
    boardResponse.headers["cache-control"] !== "no-store"
  ) {
    throw new Error("Fixture mode did not serve a valid Board.");
  }
  const undeclared = await app.inject({ method: "GET", url: "/v1/raw" });
  if (undeclared.statusCode !== 404) {
    throw new Error("Fixture mode exposed an undeclared route.");
  }
} finally {
  await app.close();
}

process.stdout.write("Fixture mode production runtime: yes\n");
