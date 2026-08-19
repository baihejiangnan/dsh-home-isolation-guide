import { constants } from "node:fs";
import { access, mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { spawn } from "node:child_process";

const [homeArgument, profile = "tauri", port = "3081"] = process.argv.slice(2);

if (!homeArgument) {
  console.error("Usage: node launcher.mjs <new-dsh-home> [profile] [port]");
  process.exit(2);
}

const dshHome = resolve(homeArgument);

try {
  await access(dshHome, constants.F_OK);
  throw new Error(`DSH_HOME already exists: ${dshHome}`);
} catch (error) {
  if (error.code !== "ENOENT") throw error;
}

const profileDir = resolve(dshHome, "profiles", profile);
await mkdir(profileDir, { recursive: true });

const manifest = {
  name: `dsh-profile-${profile}`,
  private: true,
  dependencies: {},
  dsh: {
    profile: {
      bundles: ["@deepseek-ai/dsh-base", "@deepseek-ai/dsh-web-app"],
    },
  },
};

await writeFile(
  resolve(profileDir, "package.json"),
  `${JSON.stringify(manifest, null, 2)}\n`,
  "utf8",
);
await writeFile(
  resolve(profileDir, "cordis.patch.yml"),
  "# Profile-local overrides belong here. An empty patch must be an array.\n[]\n",
  "utf8",
);

const dshCommand = process.env.DSH_BIN || "dsh";
const child = spawn(
  dshCommand,
  ["--profile", profile, "--host", "127.0.0.1", "--port", port],
  {
    stdio: "inherit",
    shell: process.platform === "win32",
    env: {
      ...process.env,
      DSH_HOME: dshHome,
      DSH_TELEMETRY_DISABLED: "1",
    },
  },
);

child.on("error", (error) => {
  console.error(`Failed to launch ${dshCommand}: ${error.message}`);
  process.exitCode = 1;
});

child.on("exit", (code, signal) => {
  if (signal) console.error(`DSH stopped by signal ${signal}`);
  process.exitCode = code ?? 1;
});
