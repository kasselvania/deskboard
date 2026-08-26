import { writeFile } from "node:fs/promises";
import { join } from "node:path";

const [outputDirectory] = process.argv.slice(2);
if (!outputDirectory) {
  throw new Error("Synthetic payload directory is required.");
}

function jsonBodyOfSize(size) {
  const prefix = '{"padding":"';
  const suffix = '"}';
  if (size < prefix.length + suffix.length) {
    throw new Error("Synthetic payload size is invalid.");
  }
  return `${prefix}${"x".repeat(size - prefix.length - suffix.length)}${suffix}`;
}

for (const [name, size] of [
  ["source-at-limit.json", 1_048_576],
  ["source-over-limit.json", 1_048_577],
  ["status-at-limit.json", 262_144],
  ["status-over-limit.json", 262_145],
]) {
  await writeFile(join(outputDirectory, name), jsonBodyOfSize(size), {
    mode: 0o600,
  });
}
