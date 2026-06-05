# SeaArt AI CLI Installation Guide for Agents

## For Humans

Copy this prompt to your local AI agent, such as Claude Code or Codex:

```text
Install SeaArt AI from https://public.cdn.seaspark.ai/ai-tool/install.md
```

---

## For AI Agents

### Goal

Install SeaArt AI CLI for the current user and install SeaArt skill files for the user's local AI tools when available. The default installer does not install `seaart-mcp`; use `install.sh mcp` when the user explicitly wants the MCP binary.

### Boundaries

When installing SeaArt AI CLI, stay within these limits:

- Do not use `sudo` or request administrator privileges.
- Do not modify system-protected directories.
- Do not install project-level skills or write `.claude/`, `.agents/`, `.gemini/`, or `.openclaw/` into the user's current project.
- Do not use an untrusted mirror if the official download fails.
- Explain the commands you are about to run before running them.
- Prefer temporary files under the OS temp directory, not the user's project directory.

### Release URLs

Base URL:

```text
https://public.cdn.seaspark.ai/ai-tool
```

Latest release directory:

```text
https://public.cdn.seaspark.ai/ai-tool/release/latest
```

This guide URL:

```text
https://public.cdn.seaspark.ai/ai-tool/install.md
```

### Release file naming

Release artifacts follow this naming pattern:

| Platform | Standalone binary file | Archive file |
|----------|------------------------|--------------|
| macOS amd64 | `seaart-darwin-amd64` | `seaart-darwin-amd64.tar.gz` |
| macOS arm64 | `seaart-darwin-arm64` | `seaart-darwin-arm64.tar.gz` |
| Linux amd64 | `seaart-linux-amd64` | `seaart-linux-amd64.tar.gz` |
| Linux arm64 | `seaart-linux-arm64` | `seaart-linux-arm64.tar.gz` |
| Linux 386 | `seaart-linux-386` | `seaart-linux-386.tar.gz` |
| Windows amd64 | `seaart-windows-amd64.exe` | `seaart-windows-amd64.zip` |
| Windows arm64 | `seaart-windows-arm64.exe` | `seaart-windows-arm64.zip` |
| Windows 386 | `seaart-windows-386.exe` | `seaart-windows-386.zip` |

The extracted package contains the executable renamed to `seaart` on macOS/Linux and `seaart.exe` on Windows, the optional `seaart-mcp` binary, plus the optional `skills/` directory when skill files are included. The default `install.sh` path installs only `seaart` and skills; `install.sh mcp` installs only `seaart-mcp`.

### User-level skill directories

Install skills only at user scope:

| Platform | User-level skill directory |
|----------|----------------------------|
| Claude Code | `~/.claude/skills/seaartai` |
| Codex | `~/.codex/skills/seaartai` |
| Gemini CLI | `~/.gemini/skills/seaartai` |
| OpenClaw | `~/.openclaw/skills/seaartai` |

If you cannot detect a supported AI tool, install only the CLI and tell the user how to add skills later.

---

## macOS / Linux

### Step 1: Detect the environment

Detect the OS, shell, CPU architecture, and installed AI tool directories.

Use user-level install only. The default command should include `-y` and `--scope user`.

### Step 2: Install

Recommended command:

```bash
curl -fsSL https://public.cdn.seaspark.ai/ai-tool/release/latest/install.sh | bash -s -- -y --scope user
```

If you can confidently detect platforms, pass them explicitly. For example:

```bash
curl -fsSL https://public.cdn.seaspark.ai/ai-tool/release/latest/install.sh | bash -s -- -y --scope user --platform claude-code,codex
```

Do not use `--scope project` unless the user explicitly asks for project-level installation.

### Step 3: Verify

Run:

```bash
command -v seaart
seaart version
seaart --help
```

### Optional: install only SeaArt MCP

When the user explicitly wants only the MCP binary, run:

```bash
curl -fsSL https://public.cdn.seaspark.ai/ai-tool/release/latest/install.sh | bash -s -- mcp -y
```

Verify:

```bash
command -v seaart-mcp
seaart-mcp --help
```

This command does not install the `seaart` CLI or skill files.

### Step 4: Report

Report these items to the user:

- SeaArt CLI version
- `seaart` command path
- Skill platform(s) installed
- User-level skill path(s)
- Any PATH reload action needed

---

## Windows

### Step 1: Detect architecture

Map the Windows CPU architecture to a release archive:

| Architecture | Archive |
|--------------|---------|
| x64 / amd64 | `seaart-windows-amd64.zip` |
| arm64 | `seaart-windows-arm64.zip` |
| x86 / 386 | `seaart-windows-386.zip` |

### Step 2: Download and extract

Use the OS temp directory for downloads and extraction.

PowerShell example:

```powershell
$BaseUrl = 'https://public.cdn.seaspark.ai/ai-tool/release/latest'
$Archive = 'seaart-windows-amd64.zip'
$TempRoot = Join-Path $env:TEMP ('seaart-install-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null
$ZipPath = Join-Path $TempRoot $Archive
Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/$Archive" -OutFile $ZipPath -ErrorAction Stop
Expand-Archive -LiteralPath $ZipPath -DestinationPath $TempRoot -Force
```

Choose the archive that matches the detected architecture.

### Step 3: Install the binary

Install `seaart.exe` into a user-level directory. Recommended path:

```text
%LOCALAPPDATA%\Programs\SeaArt\bin\seaart.exe
```

PowerShell example:

```powershell
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\SeaArt\bin'
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $TempRoot 'seaart.exe') -Destination (Join-Path $InstallDir 'seaart.exe') -Force
```

If the directory is not in PATH, tell the user to add it to the user PATH. Do not modify machine-level PATH.

### Step 4: Install user-level skills

If the extracted package contains `skills/`, copy the skill files only to user-level directories.

PowerShell examples:

```powershell
$SkillsRoot = Join-Path $TempRoot 'skills'

$ClaudeSkill = Join-Path $SkillsRoot 'claude-code\SKILL.md'
if (Test-Path -LiteralPath $ClaudeSkill) {
  $Dest = Join-Path $HOME '.claude\skills\seaartai'
  New-Item -ItemType Directory -Path $Dest -Force | Out-Null
  Copy-Item -LiteralPath $ClaudeSkill -Destination (Join-Path $Dest 'SKILL.md') -Force
}

$CodexSkill = Join-Path $SkillsRoot 'codex\SKILL.md'
if (Test-Path -LiteralPath $CodexSkill) {
  $Dest = Join-Path $HOME '.codex\skills\seaartai'
  New-Item -ItemType Directory -Path $Dest -Force | Out-Null
  Copy-Item -LiteralPath $CodexSkill -Destination (Join-Path $Dest 'SKILL.md') -Force
}
```

Apply the same pattern for `gemini-cli` and `openclaw` when those tools are present.

### Step 5: Verify

Run the installed executable directly first:

```powershell
$SeaArtExe = Join-Path $env:LOCALAPPDATA 'Programs\SeaArt\bin\seaart.exe'
& $SeaArtExe version
& $SeaArtExe --help
```

If the install directory is already in PATH, also run:

```powershell
seaart version
```

### Step 6: Report

Always report these items to the user:

- SeaArt CLI version
- Installed executable path
- Whether `seaart` is available in PATH
- User-level skill path(s) installed
- Any manual PATH step still required

---

## Final verification checklist

Before saying installation is complete, verify:

- The CLI executable exists.
- The CLI can print version or help output.
- Skills were installed only to user-level directories when applicable.
- No files were written into the user's project directory.
- The final report includes version, executable path, skill path(s), and PATH status.

## Troubleshooting

### Download failed

Report the failed official URL and stop. Do not switch to unofficial mirrors.

### Archive extraction failed

Report that the release archive could not be extracted and stop. Do not continue with partial files.

### PATH is not updated

Tell the user which directory should be added to user PATH. Do not modify system PATH.

### No AI tool detected

Install only SeaArt CLI and tell the user no supported AI tool was detected for skill installation.
