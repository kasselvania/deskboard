import { readFile } from "node:fs/promises";

const [databasePath, sourcePath, statusPath] = process.argv.slice(2);
if (!databasePath || !sourcePath || !statusPath) {
  throw new Error("Synthetic Phase 3C seed configuration is invalid.");
}

const { AppleSourceMirror } = await import(
  "/app/apps/api/dist/apple-source-mirror/index.js"
);
const sourceEnvelope = JSON.parse(await readFile(sourcePath, "utf8"));
const statusSnapshot = JSON.parse(await readFile(statusPath, "utf8"));
const mirror = new AppleSourceMirror({ databasePath });

try {
  const sourceResult = mirror.apply(sourceEnvelope);
  const statusResult = mirror.applyBridgeStatus(statusSnapshot);
  if (sourceResult.kind !== "applied" || statusResult.kind !== "applied") {
    throw new Error("Synthetic Phase 3C seed was not applied.");
  }
} finally {
  mirror.close();
}

process.stdout.write("Synthetic Phase 3C database seeded: yes\n");
