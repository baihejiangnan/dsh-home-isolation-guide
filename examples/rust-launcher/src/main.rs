use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::{Command, ExitCode, Stdio};

fn main() -> ExitCode {
    match run() {
        Ok(code) => ExitCode::from(code),
        Err(error) => {
            eprintln!("{error}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<u8, String> {
    let mut args = env::args().skip(1);
    let home = args
        .next()
        .ok_or("Usage: dsh-isolated-launcher <new-dsh-home> [profile] [port]")?;
    let profile = args.next().unwrap_or_else(|| "tauri".to_string());
    let port = args.next().unwrap_or_else(|| "3081".to_string());
    let home = PathBuf::from(home);

    if home.exists() {
        return Err(format!(
            "DSH_HOME already exists. Choose a new path: {}",
            home.display()
        ));
    }

    let profile_dir = home.join("profiles").join(&profile);
    fs::create_dir_all(&profile_dir).map_err(|error| error.to_string())?;

    let manifest = format!(
        concat!(
            "{{\n",
            "  \"name\": \"dsh-profile-{profile}\",\n",
            "  \"private\": true,\n",
            "  \"dependencies\": {{}},\n",
            "  \"dsh\": {{\n",
            "    \"profile\": {{\n",
            "      \"bundles\": [\n",
            "        \"@deepseek-ai/dsh-base\",\n",
            "        \"@deepseek-ai/dsh-web-app\"\n",
            "      ]\n",
            "    }}\n",
            "  }}\n",
            "}}\n"
        ),
        profile = profile
    );
    fs::write(profile_dir.join("package.json"), manifest).map_err(|error| error.to_string())?;
    fs::write(
        profile_dir.join("cordis.patch.yml"),
        "# Profile-local overrides belong here. An empty patch must be an array.\n[]\n",
    )
    .map_err(|error| error.to_string())?;

    let dsh = env::var("DSH_BIN").unwrap_or_else(|_| "dsh".to_string());
    let status = Command::new(dsh)
        .args([
            "--profile",
            &profile,
            "--host",
            "127.0.0.1",
            "--port",
            &port,
        ])
        .env("DSH_HOME", &home)
        .env("DSH_TELEMETRY_DISABLED", "1")
        .stdin(Stdio::null())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .map_err(|error| format!("Failed to launch DSH: {error}"))?;

    Ok(status.code().unwrap_or(1).clamp(0, 255) as u8)
}
