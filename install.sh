#!/bin/sh
# install.sh — SeaArt CLI installer with skill support for 4 AI platforms
#
# Features:
#   1. Remote install from dist-server (--source, SEAART_INSTALL_SOURCE, or DEFAULT_SOURCE_URL)
#   2. Default install path downloads a packaged release archive, then installs
#      both the binary and skill files from the extracted package
#   3. Local install from downloaded package (-f/--file .tar.gz/.zip)
#   4. Skill install for: Claude Code, Open Claw, Gemini CLI, Codex
#   5. Three install scopes: project-level, user-level, system-level
#   6. Auto-detects platforms via feature directories
#   7. Default overwrite on reinstall (Y/n prompt)
#
# Usage:
#   ./install.sh [options]                            # download release archive, install binary + optional skill
#   ./install.sh mcp [options]                        # install only seaart-mcp
#   ./install.sh -f <package.tar.gz|package.zip> [options]
#   ./install.sh mcp -f <package.tar.gz|package.zip> [options]
#   ./install.sh install-skill --source <url> [options]
#   ./install.sh install-skill -f <package.tar.gz|package.zip> [options]
#   ./install.sh uninstall-skill [options]
#
# Options:
#   --source        Base URL of the dist-server. Priority: --source > SEAART_INSTALL_SOURCE > default.
#   --version       Release version (default: "latest").
#   --install-dir   Override binary installation directory (default: auto-detect).
#   --platform      Comma-separated skill platforms (claude-code,openclaw,gemini-cli,codex).
#   --project-dir   Target project directory for project-level skill files.
#   --scope         Skill install scope: user (default), project, system.
#   -f, --file      Install from a local release package (.tar.gz or .zip).
#   -y, --yes       Skip all prompts; use defaults (overwrite, auto-detect, user scope).
#   --no-modify-path
#                    Do not modify shell profile even when install dir is not in PATH.
#   -h, --help      Show help.
set -e

# ---------------------------------------------------------------------------
# Global defaults
# ---------------------------------------------------------------------------
DEFAULT_SOURCE_URL="https://github.com/seaartpublic/cli/releases"
YES_MODE="0"
NO_MODIFY_PATH="0"
PATH_WAS_MODIFIED="0"
PATH_MODIFIED_PROFILE=""
PATH_EXPORT_LINE=""
INSTALL_DIR_SOURCE=""
INSTALL_DIR_REASON=""
ACTIVE_SEAART_PATH=""
ACTIVE_SEAART_MCP_PATH=""
TARGET_MCP_BIN=""
PACKAGE_MCP_BINARY=""
INSTALL_ACCEPTANCE_STATE="pending"
INSTALL_ACCEPTANCE_MESSAGE=""
CLEANED_OLD_BINARIES=""

print_help() {
  cat <<'HELPEOF'
SeaArt CLI installer

Usage:
  ./install.sh [options]
  ./install.sh mcp [options]
  ./install.sh -f <package.tar.gz|package.zip> [options]
  ./install.sh mcp -f <package.tar.gz|package.zip> [options]
  ./install.sh install-skill --source <url> [options]
  ./install.sh install-skill -f <package.tar.gz|package.zip> [options]
  ./install.sh uninstall-skill [options]

Options:
  --source        Base URL of the dist-server. Priority: --source > SEAART_INSTALL_SOURCE > default.
  --version       Release version (default: "latest").
  --install-dir   Override binary installation directory.
  --platform      Comma-separated skill platforms:
                    claude-code, openclaw, gemini-cli, codex
  --project-dir   Target project directory for project-level skill files.
  --scope         Skill install scope: user (default), project, system.
  -f, --file      Install from a local release package (.tar.gz or .zip).
  -y, --yes       Skip all prompts and use defaults (overwrite, auto-detect, user scope).
                  Also auto-updates PATH profile when needed.
  --no-modify-path
                  Do not modify shell profile even when install dir is not in PATH.
  -h, --help      Show help.

Skill Scopes:
  project   Install to project directory (e.g. .claude/skills/seaartai/)
  user      Install to user home (e.g. ~/.claude/skills/seaartai/)
  system    Not supported — falls back to user-level

Platform auto-detection:
  If --platform is not specified, detects installed platforms by checking:
    .claude/    → claude-code
    .openclaw/  → openclaw
    .gemini/    → gemini-cli
    ~/.codex/config.toml or .agents/ → codex

Examples:
  ./install.sh                                     # use default server
  ./install.sh mcp                                 # install only seaart-mcp
  ./install.sh --source http://192.168.1.100:34362
  SEAART_INSTALL_SOURCE=http://192.168.1.100:34362 ./install.sh
  ./install.sh --platform claude-code --scope user
  ./install.sh -f seaart-darwin-arm64.tar.gz
  ./install.sh mcp -f seaart-darwin-arm64.tar.gz
  ./install.sh -f seaart-darwin-arm64.tar.gz --platform claude-code,openclaw
  ./install.sh install-skill --platform gemini-cli --scope user
  ./install.sh install-skill -f seaart-darwin-arm64.tar.gz --platform codex
  ./install.sh uninstall-skill --scope user
  ./install.sh uninstall-skill --project-dir /path/to/project
HELPEOF
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
die() {
  echo "Error: $*" >&2
  exit 1
}

info() {
  echo "==> $*"
}

# prompt()  —  safe user-input wrapper
# Usage: prompt [--default VAL] [--choices "a b c"] "Question text" VARNAME
#   -t 0  →  read </dev/tty  (usable in curl|bash)
#   -t 0 false → echo "(using default: VAL)" and assign default
# --yes flag sets YES_MODE=1, which makes every prompt take its default immediately.
prompt() {
  _prompt_default=""
  _prompt_choices=""
  while [ $# -gt 2 ]; do
    case "$1" in
      --default) _prompt_default="$2"; shift 2 ;;
      --choices) _prompt_choices="$2"; shift 2 ;;
      *) break ;;
    esac
  done
  _prompt_text="$1"
  _prompt_var="$2"

  if [ "$YES_MODE" = "1" ]; then
    printf '%s %s (--yes → using default)\n' "$_prompt_text" "${_prompt_default:+[${_prompt_default}]}"
    eval "${_prompt_var}=\"\$_prompt_default\""
    return 0
  fi

  if [ -t 0 ]; then
    printf '%s ' "$_prompt_text"
    if [ -n "$_prompt_default" ]; then
      printf '[%s] ' "$_prompt_default"
    fi
    read _prompt_val </dev/tty || _prompt_val=""
    if [ -z "$_prompt_val" ] && [ -n "$_prompt_default" ]; then
      _prompt_val="$_prompt_default"
    fi
  else
    # non-interactive (pipe): use default silently
    if [ -n "$_prompt_default" ]; then
      echo "$_prompt_text ($_prompt_default)"
      _prompt_val="$_prompt_default"
    else
      # no default and no terminal — still try /dev/tty as last resort
      printf '%s ' "$_prompt_text"
      read _prompt_val </dev/tty 2>/dev/null || _prompt_val=""
    fi
  fi
  eval "${_prompt_var}=\"\$_prompt_val\""
}

# ---------------------------------------------------------------------------
# Skill platform definitions
# ---------------------------------------------------------------------------
SKILL_PLATFORMS="claude-code openclaw gemini-cli codex"

skill_install_dir_project() {
  case "$1" in
    claude-code) echo ".claude/skills/seaartai" ;;
    openclaw)    echo ".openclaw/skills/seaartai" ;;
    gemini-cli)  echo ".gemini/skills/seaartai" ;;
    codex)       echo ".agents/skills/seaartai" ;;
    *)           return 1 ;;
  esac
}

skill_install_dir_user() {
  case "$1" in
    claude-code) echo "${HOME}/.claude/skills/seaartai" ;;
    openclaw)    echo "${HOME}/.openclaw/skills/seaartai" ;;
    gemini-cli)  echo "${HOME}/.gemini/skills/seaartai" ;;
    codex)       echo "${HOME}/.codex/skills/seaartai" ;;
    *)           return 1 ;;
  esac
}

skill_install_dir_system() {
  # AI tools don't natively support system-level skill directories.
  # Fall back to user-level with a warning.
  echo "  Warning: system-level skill install is not supported by AI tools." >&2
  echo "  Falling back to user-level." >&2
  skill_install_dir_user "$1"
}

resolve_skill_dir() {
  _platform="$1"
  case "$SCOPE" in
    user)
      skill_install_dir_user "$_platform"
      ;;
    system)
      skill_install_dir_system "$_platform"
      ;;
    *)
      _prefix="${PROJECT_DIR:-.}"
      _rel=$(skill_install_dir_project "$_platform") || return 1
      echo "${_prefix}/${_rel}"
      ;;
  esac
}

platform_detect_dir() {
  case "$1" in
    claude-code) echo ".claude" ;;
    openclaw)    echo ".openclaw" ;;
    gemini-cli)  echo ".gemini" ;;
    codex)       echo "" ;; # special: check ~/.codex/config.toml and .agents/
    *)           echo "" ;;
  esac
}

auto_detect_platforms() {
  _detected=""
  for _p in $SKILL_PLATFORMS; do
    _dir=$(platform_detect_dir "$_p")
    if [ "$_p" = "codex" ]; then
      # Codex: check ~/.codex/config.toml OR .agents/ directory
      if [ -f "${HOME}/.codex/config.toml" ] || [ -d "./.agents" ]; then
        _detected="${_detected}${_p} "
      fi
    elif [ -n "$_dir" ] && [ -d "./${_dir}" ]; then
      _detected="${_detected}${_p} "
    fi
  done
  echo "$_detected" | sed 's/ *$//'
}

validate_platform() {
  for p in $SKILL_PLATFORMS; do
    if [ "$1" = "$p" ]; then
      return 0
    fi
  done
  return 1
}

copy_with_prompt() {
  _src="$1"
  _dst="$2"

  if [ -f "$_dst" ]; then
    prompt --default "y" "  File exists: $(basename "$_dst"). Overwrite?" _answer
    case "$_answer" in
      n|N)
        info "  Skipped: $(basename "$_dst")"
        return 0
        ;;
    esac
  fi

  cp "$_src" "$_dst"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

path_contains_dir() {
  _dir="$1"
  case ":${PATH}:" in
    *":${_dir}:"*) return 0 ;;
    *) return 1 ;;
  esac
}

is_writable_existing_dir() {
  [ -n "$1" ] && [ -d "$1" ] && [ -w "$1" ]
}

ensure_dir_exists() {
  _dir="$1"
  mkdir -p "$_dir" || die "Cannot create directory: $_dir"
}

resolve_binary_install_dir() {
  INSTALL_DIR_REASON=""

  if [ -n "$INSTALL_DIR" ]; then
    TARGET_DIR="$INSTALL_DIR"
    ensure_dir_exists "$TARGET_DIR"
    INSTALL_DIR_SOURCE="explicit"
  elif [ "$GOOS" = "windows" ]; then
    if [ -n "$LOCALAPPDATA" ]; then
      TARGET_DIR="${LOCALAPPDATA}/Programs/SeaArt/bin"
    elif [ -n "$USERPROFILE" ]; then
      TARGET_DIR="${USERPROFILE}/AppData/Local/Programs/SeaArt/bin"
    else
      TARGET_DIR="${HOME}/AppData/Local/Programs/SeaArt/bin"
    fi
    ensure_dir_exists "$TARGET_DIR"
    INSTALL_DIR_SOURCE="windows-default"
  else
    if [ -d "/usr/local/bin" ] && [ -w "/usr/local/bin" ]; then
      TARGET_DIR="/usr/local/bin"
      INSTALL_DIR_SOURCE="usr-local"
      INSTALL_DIR_REASON="preferred default location"
    else
      TARGET_DIR="${HOME}/.local/bin"
      ensure_dir_exists "$TARGET_DIR"
      INSTALL_DIR_SOURCE="local-bin"
      if [ -d "/usr/local/bin" ]; then
        INSTALL_DIR_REASON="/usr/local/bin is in PATH but not writable by the current user"
      else
        INSTALL_DIR_REASON="/usr/local/bin is unavailable, so the installer fell back to ~/.local/bin"
      fi
    fi
  fi

  if [ -z "$INSTALL_DIR_REASON" ]; then
    case "$INSTALL_DIR_SOURCE" in
      explicit) INSTALL_DIR_REASON="install directory set by --install-dir" ;;
      windows-default) INSTALL_DIR_REASON="default Windows install location" ;;
    esac
  fi

  if [ "$GOOS" = "windows" ]; then
    TARGET_BIN="${TARGET_DIR}/seaart.exe"
    TARGET_MCP_BIN="${TARGET_DIR}/seaart-mcp.exe"
  else
    TARGET_BIN="${TARGET_DIR}/seaart"
    TARGET_MCP_BIN="${TARGET_DIR}/seaart-mcp"
  fi
}

run_seaart_subcommand() {
  _bin="$1"
  _subcommand="$2"

  if "$_bin" "$_subcommand" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

run_seaart_version_check() {
  if command -v seaart >/dev/null 2>&1; then
    if run_seaart_subcommand seaart version; then
      return 0
    fi
  fi
  run_seaart_subcommand "$TARGET_BIN" version
}

is_recognizable_seaart_binary() {
  _candidate="$1"
  [ -f "$_candidate" ] || return 1
  [ -x "$_candidate" ] || return 1

  if run_seaart_subcommand "$_candidate" version; then
    return 0
  fi

  "$_candidate" --help >/dev/null 2>&1
}

install_dir_reason_label() {
  printf '%s\n' "$INSTALL_DIR_REASON"
}

build_path_export_line() {
  PATH_EXPORT_LINE='# Added by SeaArt CLI installer
if [ -d "$HOME/.local/bin" ]; then
    case ":$PATH:" in
        *":$HOME/.local/bin:"*)
            :
            ;;
        *)
            PATH="$HOME/.local/bin:$PATH"
            ;;
    esac
fi
export PATH'
}

profile_contains_path_export() {
  _profile="$1"
  [ -f "$_profile" ] || return 1
  grep -F "# Added by SeaArt CLI installer" "$_profile" >/dev/null 2>&1
}

append_path_to_profile() {
  _profile="$1"
  build_path_export_line

  if profile_contains_path_export "$_profile"; then
    return 0
  fi

  {
    printf '\n%s\n' "$PATH_EXPORT_LINE"
  } >> "$_profile" || return 1

  if [ -n "$PATH_MODIFIED_PROFILE" ]; then
    PATH_MODIFIED_PROFILE="${PATH_MODIFIED_PROFILE}, $_profile"
  else
    PATH_MODIFIED_PROFILE="$_profile"
  fi
  PATH_WAS_MODIFIED="1"
  return 0
}

append_path_to_candidate_profiles() {
  _profiles="${HOME}/.profile ${HOME}/.bash_profile ${HOME}/.bashrc ${HOME}/.zprofile ${HOME}/.zshrc"
  for _profile in $_profiles; do
    if ! append_path_to_profile "$_profile"; then
      echo "  Warning: Failed to update shell profile for PATH: $_profile" >&2
    fi
  done
}

maybe_configure_path_for_target_dir() {
  PATH_WAS_MODIFIED="0"
  PATH_MODIFIED_PROFILE=""

  if [ "$GOOS" = "windows" ]; then
    return 0
  fi

  if [ "$TARGET_DIR" != "${HOME}/.local/bin" ]; then
    return 0
  fi

  if path_contains_dir "$TARGET_DIR"; then
    return 0
  fi

  if [ "$NO_MODIFY_PATH" = "1" ]; then
    return 0
  fi

  _should_modify="0"
  if [ "$YES_MODE" = "1" ] || [ ! -t 0 ]; then
    _should_modify="1"
  else
    prompt --default "y" "${TARGET_DIR} is not in PATH. Update shell profiles automatically?" _modify_path_answer
    case "$_modify_path_answer" in
      y|Y|yes|YES)
        _should_modify="1"
        ;;
    esac
  fi

  if [ "$_should_modify" = "1" ]; then
    append_path_to_candidate_profiles
  fi
}

cleanup_old_seaart_binaries() {
  CLEANED_OLD_BINARIES=""

  for _candidate in "/usr/local/bin/seaart" "${HOME}/.local/bin/seaart"; do
    [ "$_candidate" = "$TARGET_BIN" ] && continue
    [ -e "$_candidate" ] || continue

    if ! is_recognizable_seaart_binary "$_candidate"; then
      echo "  Warning: Skipped unrecognized existing binary: $_candidate" >&2
      continue
    fi

    if rm -f "$_candidate" 2>/dev/null; then
      if [ -n "$CLEANED_OLD_BINARIES" ]; then
        CLEANED_OLD_BINARIES="${CLEANED_OLD_BINARIES}, $_candidate"
      else
        CLEANED_OLD_BINARIES="$_candidate"
      fi
    else
      echo "  Warning: Failed to remove old SeaArt binary: $_candidate" >&2
    fi
  done
}

install_file_atomically() {
  _source="$1"
  _target="$2"
  _tmp="${_target}.tmp.$$"

  cp "$_source" "$_tmp" || return 1
  chmod +x "$_tmp" || {
    rm -f "$_tmp"
    return 1
  }
  mv -f "$_tmp" "$_target" || {
    rm -f "$_tmp"
    return 1
  }
}

run_mcp_help_check() {
  _candidate="$1"
  [ -n "$_candidate" ] || return 0
  [ -f "$_candidate" ] || return 0

  "$_candidate" --help >/dev/null 2>&1
}

accept_installed_mcp_binary() {
  ACTIVE_SEAART_MCP_PATH="$(command -v seaart-mcp 2>/dev/null || true)"

  if [ -n "$ACTIVE_SEAART_MCP_PATH" ] && [ "$ACTIVE_SEAART_MCP_PATH" = "$TARGET_MCP_BIN" ]; then
    if run_mcp_help_check "$TARGET_MCP_BIN"; then
      INSTALL_ACCEPTANCE_STATE="success"
      INSTALL_ACCEPTANCE_MESSAGE="seaart-mcp resolves to the newly installed binary."
      return 0
    fi
    INSTALL_ACCEPTANCE_STATE="failed"
    INSTALL_ACCEPTANCE_MESSAGE="The installed MCP binary could not be executed with 'seaart-mcp --help'."
    return 1
  fi

  if [ -n "$ACTIVE_SEAART_MCP_PATH" ] && [ "$ACTIVE_SEAART_MCP_PATH" != "$TARGET_MCP_BIN" ]; then
    INSTALL_ACCEPTANCE_STATE="failed"
    INSTALL_ACCEPTANCE_MESSAGE="seaart-mcp resolves to a different binary: ${ACTIVE_SEAART_MCP_PATH}"
    return 1
  fi

  if [ "$PATH_WAS_MODIFIED" = "1" ]; then
    INSTALL_ACCEPTANCE_STATE="reload-required"
    INSTALL_ACCEPTANCE_MESSAGE="PATH profile updated. Reload your shell to use seaart-mcp from ${TARGET_MCP_BIN}."
    return 0
  fi

  INSTALL_ACCEPTANCE_STATE="failed"
  INSTALL_ACCEPTANCE_MESSAGE="seaart-mcp is not available in PATH after installation."
  return 1
}

accept_installed_binary() {
  ACTIVE_SEAART_PATH="$(command -v seaart 2>/dev/null || true)"

  if [ -n "$ACTIVE_SEAART_PATH" ] && [ "$ACTIVE_SEAART_PATH" = "$TARGET_BIN" ]; then
    if run_seaart_version_check; then
      if [ -n "$PACKAGE_MCP_BINARY" ]; then
        if ! run_mcp_help_check "$TARGET_MCP_BIN"; then
          INSTALL_ACCEPTANCE_STATE="failed"
          INSTALL_ACCEPTANCE_MESSAGE="The installed MCP binary could not be executed with 'seaart-mcp --help'. Restart MCP clients such as Cursor or Claude Code, then reinstall."
          return 1
        fi
      fi
      INSTALL_ACCEPTANCE_STATE="success"
      INSTALL_ACCEPTANCE_MESSAGE="seaart resolves to the newly installed binary."
      return 0
    fi
    INSTALL_ACCEPTANCE_STATE="failed"
    INSTALL_ACCEPTANCE_MESSAGE="The installed binary could not be executed with 'seaart version'."
    return 1
  fi

  if [ -n "$ACTIVE_SEAART_PATH" ] && [ "$ACTIVE_SEAART_PATH" != "$TARGET_BIN" ]; then
    INSTALL_ACCEPTANCE_STATE="failed"
    INSTALL_ACCEPTANCE_MESSAGE="seaart resolves to a different binary: ${ACTIVE_SEAART_PATH}"
    return 1
  fi

  if [ "$PATH_WAS_MODIFIED" = "1" ]; then
    INSTALL_ACCEPTANCE_STATE="reload-required"
    INSTALL_ACCEPTANCE_MESSAGE="PATH profile updated. Reload your shell to use seaart from ${TARGET_BIN}."
    return 0
  fi

  INSTALL_ACCEPTANCE_STATE="failed"
  INSTALL_ACCEPTANCE_MESSAGE="seaart is not available in PATH after installation."
  return 1
}

install_source_label() {
  if [ -n "$FILE_PACKAGE" ]; then
    printf '%s\n' "$FILE_PACKAGE"
  else
    printf '%s\n' "$SOURCE"
  fi
}

install_dir_source_label() {
  case "$INSTALL_DIR_SOURCE" in
    explicit) printf '%s\n' "--install-dir" ;;
    windows-default) printf '%s\n' "windows default" ;;
    usr-local) printf '%s\n' "/usr/local/bin (preferred default)" ;;
    local-bin) printf '%s\n' "~/.local/bin (fallback)" ;;
    *) printf '%s\n' "$INSTALL_DIR_SOURCE" ;;
  esac
}

candidate_install_dirs_note() {
  printf '%s\n' "/usr/local/bin and ${HOME}/.local/bin"
}

non_candidate_dirs_note() {
  printf '%s\n' "/usr/bin, /bin, /usr/sbin, /sbin are excluded because they are system-managed directories, often protected, and not intended for third-party app installs."
}

post_install_guidance() {
  echo ""
  if [ "$COMMAND" = "mcp" ]; then
    echo "SeaArt MCP installation summary"
    echo "  Binary              : ${TARGET_MCP_BIN}"
  else
    echo "SeaArt CLI installation summary"
    echo "  Binary              : ${TARGET_BIN}"
  fi
  echo "  Version             : ${VERSION}"
  echo "  Source              : $(install_source_label)"
  echo "  Install dir source  : $(install_dir_source_label)"
  echo "  Install dir reason  : $(install_dir_reason_label)"
  if [ "$COMMAND" = "mcp" ]; then
    if [ -n "$ACTIVE_SEAART_MCP_PATH" ]; then
      echo "  Active command      : ${ACTIVE_SEAART_MCP_PATH}"
    else
      echo "  Active command      : not available in current shell"
    fi
  elif [ -n "$ACTIVE_SEAART_PATH" ]; then
    echo "  Active command      : ${ACTIVE_SEAART_PATH}"
  else
    echo "  Active command      : not available in current shell"
  fi
  if [ -n "$CLEANED_OLD_BINARIES" ]; then
    echo "  Removed old binaries: ${CLEANED_OLD_BINARIES}"
  fi
  if [ "$PATH_WAS_MODIFIED" = "1" ]; then
    echo "  PATH profile updated: ${PATH_MODIFIED_PROFILE}"
  fi
  echo "  Acceptance          : ${INSTALL_ACCEPTANCE_STATE}"
  echo "  Note                : ${INSTALL_ACCEPTANCE_MESSAGE}"
  echo ""

  if [ "$INSTALL_ACCEPTANCE_STATE" = "reload-required" ] && [ -n "$PATH_MODIFIED_PROFILE" ]; then
    echo "  PATH block was written to: ${PATH_MODIFIED_PROFILE}"
    echo "  Open a new terminal, or source one of the updated files such as:"
    echo ""
    echo "    . \"${HOME}/.bash_profile\""
    echo "    . \"${HOME}/.bashrc\""
    echo "    . \"${HOME}/.zprofile\""
    echo "    . \"${HOME}/.zshrc\""
    echo "    . \"${HOME}/.profile\""
    echo ""
  elif [ "$GOOS" != "windows" ] && [ "$TARGET_DIR" = "${HOME}/.local/bin" ] && ! path_contains_dir "$TARGET_DIR" && [ "$NO_MODIFY_PATH" = "1" ]; then
    build_path_export_line
    echo "  NOTE: ${TARGET_DIR} is not in your PATH. Add the following block to your shell profile(s):"
    echo ""
    printf '%s\n' "$PATH_EXPORT_LINE"
    echo ""
  fi

  if [ "$(uname -s)" = "Darwin" ]; then
    echo "  macOS note: if macOS blocks the binary on first run, execute:"
    echo ""
    if [ "$COMMAND" = "mcp" ]; then
      echo "    xattr -d com.apple.quarantine ${TARGET_MCP_BIN}"
    else
      echo "    xattr -d com.apple.quarantine ${TARGET_BIN}"
    fi
    echo ""
  fi

  if [ "$COMMAND" = "mcp" ]; then
    echo "Run 'seaart-mcp serve' to start the MCP server."
  else
    echo "Run 'seaart --help' to get started."
  fi
}

install_binary_from_package() {
  prepare_package_from_source_or_file
  resolve_binary_install_dir

  if [ -n "$FILE_PACKAGE" ]; then
    info "Installing from local package: ${FILE_PACKAGE}"
  else
    info "Installing from downloaded package: ${PACKAGE_ARCHIVE_NAME}"
  fi
  info "Installing to ${TARGET_BIN} ..."
  install_file_atomically "$PACKAGE_BINARY" "$TARGET_BIN"
  maybe_configure_path_for_target_dir
  cleanup_old_seaart_binaries
  if ! accept_installed_binary; then
    post_install_guidance
    die "$INSTALL_ACCEPTANCE_MESSAGE"
  fi
  post_install_guidance
}

install_mcp_binary_from_package() {
  prepare_package_from_source_or_file
  resolve_binary_install_dir

  [ -n "$PACKAGE_MCP_BINARY" ] || die "package does not contain a top-level 'seaart-mcp' or 'seaart-mcp.exe' binary"

  if [ -n "$FILE_PACKAGE" ]; then
    info "Installing from local package: ${FILE_PACKAGE}"
  else
    info "Installing from downloaded package: ${PACKAGE_ARCHIVE_NAME}"
  fi
  info "Installing to ${TARGET_MCP_BIN} ..."
  install_file_atomically "$PACKAGE_MCP_BINARY" "$TARGET_MCP_BIN"
  maybe_configure_path_for_target_dir
  if ! accept_installed_mcp_binary; then
    post_install_guidance
    die "$INSTALL_ACCEPTANCE_MESSAGE"
  fi
  post_install_guidance
}

# ---------------------------------------------------------------------------
# Argument parsing (POSIX-compatible)
# ---------------------------------------------------------------------------
COMMAND=""
SOURCE="${SEAART_INSTALL_SOURCE:-}"
VERSION="latest"
INSTALL_DIR=""
PLATFORM=""
PROJECT_DIR=""
SCOPE="user"
FILE_PACKAGE=""

if [ "$#" -gt 0 ] && ! echo "$1" | grep -q '^-' ; then
  COMMAND="$1"
  shift
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --source)
      [ "$#" -ge 2 ] || die "--source requires a value"
      SOURCE="$2"
      shift 2
      ;;
    --version)
      [ "$#" -ge 2 ] || die "--version requires a value"
      VERSION="$2"
      shift 2
      ;;
    --install-dir)
      [ "$#" -ge 2 ] || die "--install-dir requires a value"
      INSTALL_DIR="$2"
      shift 2
      ;;
    --platform)
      [ "$#" -ge 2 ] || die "--platform requires a value"
      PLATFORM="$2"
      shift 2
      ;;
    --project-dir)
      [ "$#" -ge 2 ] || die "--project-dir requires a value"
      PROJECT_DIR="$2"
      shift 2
      ;;
    --scope)
      [ "$#" -ge 2 ] || die "--scope requires a value"
      case "$2" in
        project|user|system) SCOPE="$2" ;;
        *) die "Invalid scope: $2 (available: project, user, system)" ;;
      esac
      shift 2
      ;;
    -f|--file)
      [ "$#" -ge 2 ] || die "$1 requires a value"
      FILE_PACKAGE="$2"
      shift 2
      ;;
    --no-modify-path)
      NO_MODIFY_PATH="1"
      shift
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    -y|--yes)
      YES_MODE="1"
      shift
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Apply default source if neither --source, SEAART_INSTALL_SOURCE, nor --file was given
# ---------------------------------------------------------------------------
if [ -z "$SOURCE" ] && [ -z "$FILE_PACKAGE" ]; then
  SOURCE="$DEFAULT_SOURCE_URL"
fi

# ---------------------------------------------------------------------------
# Temporary workspace
# ---------------------------------------------------------------------------
TMP_DIR=$(mktemp -d)
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

PACKAGE_READY="0"
PACKAGE_ROOT=""
PACKAGE_BINARY=""
PACKAGE_SKILLS_DIR=""
PACKAGE_ARCHIVE=""
PACKAGE_ARCHIVE_NAME=""
BASE_URL=""
GOOS=""
GOARCH=""

extract_package_archive() {
  _archive="$1"
  PACKAGE_ROOT="${TMP_DIR}/package"
  rm -rf "$PACKAGE_ROOT"
  mkdir -p "$PACKAGE_ROOT"

  case "$_archive" in
    *.tar.gz)
      tar -xzf "$_archive" -C "$PACKAGE_ROOT" || die "failed to extract package: $_archive"
      ;;
    *.zip)
      if command -v unzip >/dev/null 2>&1; then
        unzip -q "$_archive" -d "$PACKAGE_ROOT" || die "failed to extract package: $_archive"
      else
        python3 - <<'PY' "$_archive" "$PACKAGE_ROOT"
import sys, zipfile
archive, outdir = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(archive) as zf:
    zf.extractall(outdir)
PY
      fi
      ;;
    *)
      die "unsupported package format: $_archive (expected .tar.gz or .zip)"
      ;;
  esac
}

prepare_package_metadata() {
  if [ -f "$PACKAGE_ROOT/seaart" ]; then
    PACKAGE_BINARY="$PACKAGE_ROOT/seaart"
  elif [ -f "$PACKAGE_ROOT/seaart.exe" ]; then
    PACKAGE_BINARY="$PACKAGE_ROOT/seaart.exe"
  else
    die "package does not contain a top-level 'seaart' or 'seaart.exe' binary"
  fi

  if [ -f "$PACKAGE_ROOT/seaart-mcp" ]; then
    PACKAGE_MCP_BINARY="$PACKAGE_ROOT/seaart-mcp"
  elif [ -f "$PACKAGE_ROOT/seaart-mcp.exe" ]; then
    PACKAGE_MCP_BINARY="$PACKAGE_ROOT/seaart-mcp.exe"
  else
    PACKAGE_MCP_BINARY=""
  fi

  PACKAGE_SKILLS_DIR="$PACKAGE_ROOT/skills"
  PACKAGE_READY="1"
}

prepare_local_package() {
  if [ "$PACKAGE_READY" = "1" ]; then
    return 0
  fi

  [ -n "$FILE_PACKAGE" ] || die "local package path is empty"
  [ -f "$FILE_PACKAGE" ] || die "package file not found: $FILE_PACKAGE"

  info "Extracting package: ${FILE_PACKAGE}"
  PACKAGE_ARCHIVE="$FILE_PACKAGE"
  PACKAGE_ARCHIVE_NAME=$(basename "$FILE_PACKAGE")
  extract_package_archive "$FILE_PACKAGE"
  prepare_package_metadata
}

build_archive_name() {
  detect_platform
  PACKAGE_ARCHIVE_NAME="seaart-${GOOS}-${GOARCH}"
  if [ "$GOOS" = "windows" ]; then
    PACKAGE_ARCHIVE_NAME="${PACKAGE_ARCHIVE_NAME}.zip"
  else
    PACKAGE_ARCHIVE_NAME="${PACKAGE_ARCHIVE_NAME}.tar.gz"
  fi
}

prepare_remote_package() {
  if [ "$PACKAGE_READY" = "1" ]; then
    return 0
  fi

  build_archive_name
  if [ "$VERSION" = "latest" ]; then
    BASE_URL="${SOURCE}/latest/download"
  else
    BASE_URL="${SOURCE}/download/${VERSION}"
  fi
  PACKAGE_ARCHIVE="${TMP_DIR}/${PACKAGE_ARCHIVE_NAME}"

  info "Installing from: ${SOURCE}"
  info "Installing version: ${VERSION}"
  info "Downloading package: ${PACKAGE_ARCHIVE_NAME} ..."
  if ! curl -fSL --connect-timeout 10 --max-time 180 --progress-bar -o "$PACKAGE_ARCHIVE" "${BASE_URL}/${PACKAGE_ARCHIVE_NAME}"; then
    die "Download failed: ${BASE_URL}/${PACKAGE_ARCHIVE_NAME}"
  fi

  info "Extracting package: ${PACKAGE_ARCHIVE_NAME}"
  extract_package_archive "$PACKAGE_ARCHIVE"
  prepare_package_metadata
}

prepare_package_from_source_or_file() {
  if [ -n "$FILE_PACKAGE" ]; then
    prepare_local_package
  else
    prepare_remote_package
  fi
}

require_source_or_file() {
  if [ -n "$SOURCE" ] && [ -n "$FILE_PACKAGE" ]; then
    die "--source and --file cannot be used together"
  fi
  if [ -z "$SOURCE" ] && [ -z "$FILE_PACKAGE" ]; then
    die "either --source or --file is required"
  fi
}

# ---------------------------------------------------------------------------
# Scope selection prompt
# ---------------------------------------------------------------------------
prompt_scope() {
  if [ -n "$SCOPE_SELECTED" ]; then
    return 0
  fi

  # If --scope was explicitly passed, don't prompt again
  SCOPE_SELECTED="1"

  echo ""
  echo "Select skill installation scope:"
  echo "  1) User-level    (all projects for this user, ~/.claude/skills/ etc.)"
  echo "  2) Project-level (this project only, .claude/skills/ etc.)"
  echo "  3) System-level  (not supported by AI tools, falls back to user-level)"
  echo ""
  prompt --default "1" "Choice" _sc
  case "$_sc" in
    2) SCOPE="project" ;;
    3) SCOPE="system" ;;
    *) SCOPE="user" ;;
  esac
  info "Skill scope: ${SCOPE}"
}

# ---------------------------------------------------------------------------
# Skill installation
# ---------------------------------------------------------------------------
download_skill_file() {
  _remote_path="$1"
  _local_path="$2"
  _tmp_file="${TMP_DIR}/$(basename "$_local_path")"
  _url="${BASE_URL}/skills/${_remote_path}"

  if ! curl -fSL --connect-timeout 10 --max-time 30 -o "$_tmp_file" "$_url" 2>/dev/null; then
    echo "  Warning: Failed to download ${_remote_path}, skipping." >&2
    return 0
  fi

  copy_with_prompt "$_tmp_file" "$_local_path"
}

copy_skill_file_from_package() {
  _src="$1"
  _dst="$2"

  if [ ! -f "$_src" ]; then
    echo "  Warning: Missing package file $(basename "$_src"), skipping." >&2
    return 0
  fi

  copy_with_prompt "$_src" "$_dst"
}

install_platform_skill() {
  _platform="$1"
  _dest_dir=$(resolve_skill_dir "$_platform") || die "Unknown platform: $_platform"

  info "Installing skill for ${_platform} (scope: ${SCOPE}) -> ${_dest_dir}"
  mkdir -p "$_dest_dir"

  prepare_package_from_source_or_file
  if [ ! -d "$PACKAGE_SKILLS_DIR" ]; then
    echo "  Warning: package does not contain skills/, skipping skill installation." >&2
    return 0
  fi
  copy_skill_file_from_package "$PACKAGE_SKILLS_DIR/${_platform}/SKILL.md" "$_dest_dir/SKILL.md"

  info "  Skill for ${_platform} installed."
}

interactive_select_platforms() {
  echo ""
  echo "Select AI coding platforms to install SeaArt skill:"
  echo "  1) Claude Code"
  echo "  2) Open Claw"
  echo "  3) Gemini CLI"
  echo "  4) Codex"
  echo "  5) All"
  echo "  0) Skip"
  echo ""
  prompt --default "5" "Enter choice(s), space-separated (e.g. 1 3 or 5)" _choices

  _selected=""
  for _c in $_choices; do
    case "$_c" in
      1) _selected="${_selected} claude-code" ;;
      2) _selected="${_selected} openclaw" ;;
      3) _selected="${_selected} gemini-cli" ;;
      4) _selected="${_selected} codex" ;;
      5) _selected="claude-code openclaw gemini-cli codex" ;;
      0) return 0 ;;
      *) echo "  Warning: unknown choice '$_c', ignored." ;;
    esac
  done

  echo "$_selected" | tr ' ' '\n' | sed '/^$/d' | sort -u | tr '\n' ' ' | sed 's/^ *//;s/ *$//'
}

cmd_install_skill() {
  _selected=""

  if [ -n "$PLATFORM" ]; then
    _selected=$(echo "$PLATFORM" | tr ',' ' ')
    for _p in $_selected; do
      validate_platform "$_p" || die "Unknown platform: $_p (available: $SKILL_PLATFORMS)"
    done
  else
    # Auto-detect platforms
    if [ ! -t 0 ]; then
      _detected=$(auto_detect_platforms)
      if [ -n "$_detected" ]; then
        info "Auto-detected platforms: $_detected"
        _selected="$_detected"
      else
        info "Non-interactive terminal, no platforms auto-detected, skipping skill installation."
        info "Use --platform to specify platforms."
        return 0
      fi
    else
      _detected=$(auto_detect_platforms)
      if [ -n "$_detected" ]; then
        echo ""
        prompt --default "y" "Auto-detected platforms: $_detected. Install for these?" _auto_confirm
        case "$_auto_confirm" in
          n|N)
            _selected=$(interactive_select_platforms)
            ;;
          *)
            _selected="$_detected"
            ;;
        esac
      else
        _selected=$(interactive_select_platforms)
      fi
    fi
  fi

  if [ -z "$_selected" ]; then
    info "No platforms selected, skipping skill installation."
    return 0
  fi

  # Prompt for scope
  prompt_scope

  for _p in $_selected; do
    install_platform_skill "$_p"
  done
}

cmd_uninstall_skill() {
  _project_dir="${PROJECT_DIR:-.}"
  _home="${HOME}"
  _removed=0

  for _p in $SKILL_PLATFORMS; do
    # Try project-level
    _rel_proj=$(skill_install_dir_project "$_p" 2>/dev/null) || continue
    _dest_proj="${_project_dir}/${_rel_proj}"
    if [ -d "$_dest_proj" ]; then
      rm -rf "$_dest_proj"
      info "Removed skill for ${_p} (project): ${_dest_proj}"
      _removed=$((_removed + 1))
    fi

    # Try user-level
    _dest_user=$(skill_install_dir_user "$_p" 2>/dev/null) || continue
    if [ -d "$_dest_user" ]; then
      rm -rf "$_dest_user"
      info "Removed skill for ${_p} (user): ${_dest_user}"
      _removed=$((_removed + 1))
    fi
  done

  if [ "$_removed" -eq 0 ]; then
    info "No skill files found to remove."
  else
    info "Removed skill for ${_removed} location(s)."
  fi
}

# ---------------------------------------------------------------------------
# Binary installation
# ---------------------------------------------------------------------------
detect_platform() {
  _os=$(uname -s)
  _arch=$(uname -m)

  case "$_os" in
    Linux)                 GOOS="linux" ;;
    Darwin)                GOOS="darwin" ;;
    MINGW*|MSYS*|CYGWIN*)  GOOS="windows" ;;
    *)                     die "Unsupported operating system: $_os" ;;
  esac

  case "$_arch" in
    x86_64|amd64)  GOARCH="amd64" ;;
    aarch64|arm64) GOARCH="arm64" ;;
    i386|i686|x86) GOARCH="386" ;;
    *)             die "Unsupported architecture: $_arch" ;;
  esac

  info "Detected platform: ${GOOS}/${GOARCH}"
}

install_binary_from_package() {
  prepare_package_from_source_or_file
  resolve_binary_install_dir

  if [ -n "$FILE_PACKAGE" ]; then
    info "Installing from local package: ${FILE_PACKAGE}"
  else
    info "Installing from downloaded package: ${PACKAGE_ARCHIVE_NAME}"
  fi
  info "Installing to ${TARGET_BIN} ..."
  install_file_atomically "$PACKAGE_BINARY" "$TARGET_BIN"
  maybe_configure_path_for_target_dir
  cleanup_old_seaart_binaries
  if ! accept_installed_binary; then
    post_install_guidance
    die "$INSTALL_ACCEPTANCE_MESSAGE"
  fi
  post_install_guidance
}

install_mcp_binary_from_package() {
  prepare_package_from_source_or_file
  resolve_binary_install_dir

  [ -n "$PACKAGE_MCP_BINARY" ] || die "package does not contain a top-level 'seaart-mcp' or 'seaart-mcp.exe' binary"

  if [ -n "$FILE_PACKAGE" ]; then
    info "Installing from local package: ${FILE_PACKAGE}"
  else
    info "Installing from downloaded package: ${PACKAGE_ARCHIVE_NAME}"
  fi
  info "Installing to ${TARGET_MCP_BIN} ..."
  install_file_atomically "$PACKAGE_MCP_BINARY" "$TARGET_MCP_BIN"
  maybe_configure_path_for_target_dir
  if ! accept_installed_mcp_binary; then
    post_install_guidance
    die "$INSTALL_ACCEPTANCE_MESSAGE"
  fi
  post_install_guidance
}

cmd_install_binary() {
  require_source_or_file
  install_binary_from_package
}

cmd_install_mcp() {
  require_source_or_file
  install_mcp_binary_from_package
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
case "$COMMAND" in
  "")
    cmd_install_binary
    cmd_install_skill
    ;;
  mcp)
    cmd_install_mcp
    ;;
  install-skill)
    require_source_or_file
    cmd_install_skill
    ;;
  uninstall-skill)
    cmd_uninstall_skill
    ;;
  *)
    die "Unknown command: $COMMAND (available: mcp, install-skill, uninstall-skill)"
    ;;
esac

# ---------------------------------------------------------------------------
# Argument parsing (POSIX-compatible)
# ---------------------------------------------------------------------------
COMMAND=""
SOURCE="${SEAART_INSTALL_SOURCE:-}"
VERSION="latest"
INSTALL_DIR=""
PLATFORM=""
PROJECT_DIR=""
SCOPE="user"
FILE_PACKAGE=""

if [ "$#" -gt 0 ] && ! echo "$1" | grep -q '^-'; then
  COMMAND="$1"
  shift
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --source)
      [ "$#" -ge 2 ] || die "--source requires a value"
      SOURCE="$2"
      shift 2
      ;;
    --version)
      [ "$#" -ge 2 ] || die "--version requires a value"
      VERSION="$2"
      shift 2
      ;;
    --install-dir)
      [ "$#" -ge 2 ] || die "--install-dir requires a value"
      INSTALL_DIR="$2"
      shift 2
      ;;
    --platform)
      [ "$#" -ge 2 ] || die "--platform requires a value"
      PLATFORM="$2"
      shift 2
      ;;
    --project-dir)
      [ "$#" -ge 2 ] || die "--project-dir requires a value"
      PROJECT_DIR="$2"
      shift 2
      ;;
    --scope)
      [ "$#" -ge 2 ] || die "--scope requires a value"
      case "$2" in
        project|user|system) SCOPE="$2" ;;
        *) die "Invalid scope: $2 (available: project, user, system)" ;;
      esac
      shift 2
      ;;
    -f|--file)
      [ "$#" -ge 2 ] || die "$1 requires a value"
      FILE_PACKAGE="$2"
      shift 2
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    -y|--yes)
      YES_MODE="1"
      shift
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Apply default source if neither --source, SEAART_INSTALL_SOURCE, nor --file was given
# ---------------------------------------------------------------------------
if [ -z "$SOURCE" ] && [ -z "$FILE_PACKAGE" ]; then
  SOURCE="$DEFAULT_SOURCE_URL"
fi

# ---------------------------------------------------------------------------
# Temporary workspace
# ---------------------------------------------------------------------------
TMP_DIR=$(mktemp -d)
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

PACKAGE_READY="0"
PACKAGE_ROOT=""
PACKAGE_BINARY=""
PACKAGE_SKILLS_DIR=""
PACKAGE_ARCHIVE=""
PACKAGE_ARCHIVE_NAME=""
BASE_URL=""
GOOS=""
GOARCH=""

extract_package_archive() {
  _archive="$1"
  PACKAGE_ROOT="${TMP_DIR}/package"
  rm -rf "$PACKAGE_ROOT"
  mkdir -p "$PACKAGE_ROOT"

  case "$_archive" in
    *.tar.gz)
      tar -xzf "$_archive" -C "$PACKAGE_ROOT" || die "failed to extract package: $_archive"
      ;;
    *.zip)
      if command -v unzip >/dev/null 2>&1; then
        unzip -q "$_archive" -d "$PACKAGE_ROOT" || die "failed to extract package: $_archive"
      else
        python3 - <<'PY' "$_archive" "$PACKAGE_ROOT"
import sys, zipfile
archive, outdir = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(archive) as zf:
    zf.extractall(outdir)
PY
      fi
      ;;
    *)
      die "unsupported package format: $_archive (expected .tar.gz or .zip)"
      ;;
  esac
}

prepare_package_metadata() {
  if [ -f "$PACKAGE_ROOT/seaart" ]; then
    PACKAGE_BINARY="$PACKAGE_ROOT/seaart"
  elif [ -f "$PACKAGE_ROOT/seaart.exe" ]; then
    PACKAGE_BINARY="$PACKAGE_ROOT/seaart.exe"
  else
    die "package does not contain a top-level 'seaart' or 'seaart.exe' binary"
  fi

  if [ -f "$PACKAGE_ROOT/seaart-mcp" ]; then
    PACKAGE_MCP_BINARY="$PACKAGE_ROOT/seaart-mcp"
  elif [ -f "$PACKAGE_ROOT/seaart-mcp.exe" ]; then
    PACKAGE_MCP_BINARY="$PACKAGE_ROOT/seaart-mcp.exe"
  else
    PACKAGE_MCP_BINARY=""
  fi

  PACKAGE_SKILLS_DIR="$PACKAGE_ROOT/skills"
  PACKAGE_READY="1"
}
