# SeaArt CLI

[![release](https://img.shields.io/github/v/release/seaartpublic/cli?style=flat-square)](https://github.com/seaartpublic/cli/releases)
[![license](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](./LICENSE.txt)

SeaArt CLI brings SeaArt AI generation and automation workflows to your terminal. Use it to authenticate, inspect available models, generate images and videos, parse SeaArt resource URLs, check account assets, track tasks, and install optional AI-agent skills.

This repository is the public distribution and documentation repository for SeaArt CLI. The CLI implementation source code is not published here. New CLI versions are distributed through GitHub Releases.

## Contents

- [Install](#install)
- [Quickstart](#quickstart)
- [Release assets](#release-assets)
- [Commands](#commands)
- [Agent installation](#agent-installation)
- [Updating](#updating)
- [Troubleshooting](#troubleshooting)
- [Support](#support)
- [License](#license)

## Install

### One-line installer

macOS and Linux users can install the latest release with:

```bash
curl -fsSL https://raw.githubusercontent.com/seaartpublic/cli/main/install.sh | bash -s -- -y --scope user
```

If you want to install SeaArt skill files for specific AI coding tools, pass `--platform` explicitly:

```bash
curl -fsSL https://raw.githubusercontent.com/seaartpublic/cli/main/install.sh | bash -s -- -y --scope user --platform claude-code,codex
```

Supported skill platforms are:

- `claude-code`
- `openclaw`
- `gemini-cli`
- `codex`

### Install with an AI agent

You can also ask your local AI agent, such as Claude Code or Codex, to install SeaArt AI for you. Copy this prompt into the agent:

```text
Install SeaArt AI from https://raw.githubusercontent.com/seaartpublic/cli/main/install.md
```

The agent-facing installation guide is also available in this repository: [install.md](./install.md).

### Manual download

Download the archive matching your OS and CPU architecture from [GitHub Releases](https://github.com/seaartpublic/cli/releases), extract it, and place the `seaart` binary in a directory on your `PATH`.

Example release package URL:

```text
https://github.com/seaartpublic/cli/releases/download/v1.0.0/seaart-darwin-amd64.tar.gz
```

Windows users should download a `.zip` archive. macOS and Linux users should download a `.tar.gz` archive.

### Install only SeaArt MCP

When you explicitly want only the MCP binary:

```bash
curl -fsSL https://raw.githubusercontent.com/seaartpublic/cli/main/install.sh | bash -s -- mcp -y
```

Then verify:

```bash
seaart-mcp --help
```

## Quickstart

Authenticate:

```bash
seaart login
```

List models dynamically from SeaArt:

```bash
seaart models list
```

Create a text-to-image task:

```bash
seaart text2image \
  --model-id <model_id> \
  --model-ver-id <model_version_id> \
  --prompt "a cinematic robot painting in a studio"
```

Create an image edit task:

```bash
seaart image_edit \
  --model-id <model_id> \
  --model-ver-id <model_version_id> \
  --prompt "turn this into a watercolor illustration" \
  --image ./input.png
```

Check a task:

```bash
seaart task status <task_id>
```

Print version information:

```bash
seaart version
```

Run `seaart --help` or `seaart <command> --help` for the installed CLI's live help output.

## Release assets

Release archives follow the same platform naming as the SeaArt CLI release build. Each release can include standalone binaries, archive packages, `seaart-mcp`, `checksums.sha256`, `manifest.json`, `install.sh`, `install.md`, and optional `skills/` files.

| Platform | Architecture | Standalone binary | Archive |
|----------|--------------|-------------------|---------|
| macOS | amd64 | `seaart-darwin-amd64` | `seaart-darwin-amd64.tar.gz` |
| macOS | arm64 | `seaart-darwin-arm64` | `seaart-darwin-arm64.tar.gz` |
| Linux | amd64 | `seaart-linux-amd64` | `seaart-linux-amd64.tar.gz` |
| Linux | arm64 | `seaart-linux-arm64` | `seaart-linux-arm64.tar.gz` |
| Linux | 386 | `seaart-linux-386` | `seaart-linux-386.tar.gz` |
| Windows | amd64 | `seaart-windows-amd64.exe` | `seaart-windows-amd64.zip` |
| Windows | arm64 | `seaart-windows-arm64.exe` | `seaart-windows-arm64.zip` |
| Windows | 386 | `seaart-windows-386.exe` | `seaart-windows-386.zip` |

The extracted archive contains `seaart` on macOS/Linux or `seaart.exe` on Windows. Packages can also include `seaart-mcp` / `seaart-mcp.exe` and `skills/`.

## Commands

### Core

| Command | Purpose |
|---------|---------|
| `seaart version` | Print the CLI version. |
| `seaart login` | Log in to SeaArt CLI. Supports browser login and manual credentials/token flags. |
| `seaart logout` | Log out from SeaArt CLI. |

`seaart login` flags:

| Flag | Purpose |
|------|---------|
| `--token` | Manual auth token. |
| `--username` | Login email. |
| `--password` | Login password. |

### Account

| Command | Purpose |
|---------|---------|
| `seaart account` | Account commands. |
| `seaart account assets` | Get account assets summary. |

### Model discovery

| Command | Purpose |
|---------|---------|
| `seaart models` | Discover model capabilities. |
| `seaart models list` | List recommended models as Markdown. |
| `seaart models params <model_id>` | Get normalized model parameter schema. |
| `seaart loras` | Discover image LoRA capabilities. |
| `seaart loras list` | List image LoRAs by base model or model id. |

`seaart loras list` flags:

| Flag | Purpose |
|------|---------|
| `--base-model` | Image base model name. |
| `--model-id` | Resolve image base model from model detail. |

SeaArt model data is fetched dynamically. This repository does not maintain a static `MODELS.md` file.

### Image generation

| Command | Purpose |
|---------|---------|
| `seaart text2image` | Generate a text-to-image task. |
| `seaart image_edit` | Generate an image-to-image task. |

Common image flags:

| Flag | Purpose |
|------|---------|
| `--model-id` | Image model id. |
| `--model-ver-id` | Image model version id. |
| `--prompt` | Prompt text. |
| `--resolution` | Resolution like `1024x1024`. |
| `--seed` | Random seed. |
| `--gen-mode` | Generation mode. |
| `--gen-quality` | Generation quality. |
| `--generate-count` | Generate count. |
| `--no-wait` | Return task id without blocking. |
| `--estimate` | Estimate compute cost without creating an image task. |

`seaart image_edit` also supports:

| Flag | Purpose |
|------|---------|
| `--image` | Local image path or remote URL. |

### Video generation

| Command | Purpose |
|---------|---------|
| `seaart text2video` | Generate a video from a text prompt. |
| `seaart image2video` | Generate a video from first and/or last frame images. |
| `seaart reference2video` | Generate a video from prompt-bound image, video, and audio references. |

Common video flags:

| Flag | Purpose |
|------|---------|
| `--model-id` | Video model id. |
| `--model-ver-id` | Video model version id. |
| `--prompt` | Prompt text. |
| `--negative-prompt` | Negative prompt text. |
| `--duration` | Video duration in seconds. |
| `--no-wait` | Return task id without blocking. |
| `--resolution` | Video quality/resolution enum value. |
| `--aspect-ratio` | Video aspect ratio, for example `16:9`. |

`seaart image2video` frame flags:

| Flag | Purpose |
|------|---------|
| `--first-frame` | First frame image path or URL. |
| `--last-frame` | Last frame image path or URL. |

`seaart reference2video` uses prompt-bound references, for example `{{image:path-or-url}}`.

### Task status

| Command | Purpose |
|---------|---------|
| `seaart task` | Task status commands. |
| `seaart task status <task_id>` | Get task status. |

### Resource parsing

| Command | Purpose |
|---------|---------|
| `seaart parse <url>` | Parse a SeaArt resource URL into normalized JSON. |

### MCP

SeaArt also ships an optional MCP server binary named `seaart-mcp`.

| Command | Purpose |
|---------|---------|
| `seaart-mcp serve` | Run SeaArt MCP server. |
| `seaart-mcp install` | Print manual SeaArt MCP client configuration instructions. |

`seaart-mcp serve` flags:

| Flag | Purpose |
|------|---------|
| `--host` | Remote MCP host; defaults to `127.0.0.1` when `--port` is set. |
| `--port` | Remote MCP port; default `0` uses stdio mode. |

`seaart-mcp install` flags:

| Flag | Purpose |
|------|---------|
| `--platform` | MCP client platform: `claude-code`, `cursor`, `openclaw`, `gemini-cli`, `codex`. |
| `--scope` | Configuration scope: `user` or `project`. |
| `--project-dir` | Project directory for project scope. |
| `--host` | Remote MCP host for printed configuration. |
| `--port` | Remote MCP port for printed configuration. |
| `--binary` | SeaArt MCP binary path to print in MCP config. |

## Agent installation

For AI agents, see [install.md](./install.md). It describes user-level installation boundaries, supported release files, verification steps, and skill installation paths.

## Updating

Run the installer again to install the latest release:

```bash
curl -fsSL https://raw.githubusercontent.com/seaartpublic/cli/main/install.sh | bash -s -- -y --scope user
```

Or download a newer archive from [GitHub Releases](https://github.com/seaartpublic/cli/releases) and replace the binary in your `PATH`.

## Troubleshooting

### `seaart` is not found after installation

Open a new terminal or ensure the install directory is on your `PATH`. The installer prints the installed path and any PATH reload action needed.

### Download failed

Check the official release page and confirm that the matching asset exists for your platform. If the issue persists, open a GitHub Issue.

### Archive extraction failed

Confirm the downloaded file matches your OS and CPU architecture, then download it again from GitHub Releases.

### macOS blocks the binary

If macOS blocks the binary on first run, remove the quarantine attribute:

```bash
xattr -d com.apple.quarantine /path/to/seaart
```

### Model list is missing or outdated

Run:

```bash
seaart models list
```

Model information is fetched dynamically by the CLI.

## Support

- Bugs and feature requests: [GitHub Issues](https://github.com/seaartpublic/cli/issues)
- Community discussions: [GitHub Discussions](https://github.com/seaartpublic/cli/discussions)
- Product feedback: [SeaArt Featurebase](https://seaartai.featurebase.app/)

When reporting a CLI issue, include:

```bash
seaart version
seaart <command> --help
```

and the exact command that failed.

## License

[MIT](./LICENSE.txt)
