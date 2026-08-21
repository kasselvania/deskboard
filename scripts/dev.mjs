import { spawn } from "node:child_process";

const workspaceCommands = [
  ["@deskboard/api", "API"],
  ["@deskboard/web", "Web"],
];

const children = workspaceCommands.map(([workspace, label]) => {
  const child = spawn(
    "npm",
    ["run", "dev", "--workspace", workspace],
    {
      stdio: "inherit",
      shell: process.platform === "win32",
    },
  );

  child.on("error", (error) => {
    console.error(`${label} development process could not start.`, error);
  });

  return child;
});

let shuttingDown = false;

function stopChildren(signal = "SIGTERM") {
  if (shuttingDown) {
    return;
  }

  shuttingDown = true;
  for (const child of children) {
    if (!child.killed) {
      child.kill(signal);
    }
  }
}

for (const child of children) {
  child.on("exit", (code, signal) => {
    if (shuttingDown) {
      return;
    }

    stopChildren();
    process.exitCode = signal ? 1 : (code ?? 1);
  });
}

process.on("SIGINT", () => {
  stopChildren("SIGINT");
});

process.on("SIGTERM", () => {
  stopChildren("SIGTERM");
});
