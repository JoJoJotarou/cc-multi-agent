#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
VERSION="1.0.0"

DEFAULT_PLUGIN_NAME="jojojotarou-cc-multi-agent"
DEFAULT_MARKETPLACE_NAME="jojojotarou-cc-multi-agent-marketplace"
MANAGED_BEGIN="<!-- BEGIN MANAGED: MULTI-CODING-AGENTS -->"
MANAGED_END="<!-- END MANAGED: MULTI-CODING-AGENTS -->"
# Remote install defaults.
DEFAULT_REMOTE_REPO="JoJoJotarou/cc-multi-agent"
DEFAULT_REMOTE_REF="master"

TARGET="all"
SCOPE="project"
ACTIVATE_COORDINATOR="no"
DRY_RUN="no"
FORCE="no"
TARGET_PROJECT_DIR=""
INTERACTIVE="no"
HAD_ARGS="no"

WORK_DIR=""
DOWNLOAD_DIR=""
DISCOVERED_SOURCE_KIND=""
DISCOVERED_SOURCE_ROOT=""

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'Warning: %s\n' "$*" >&2
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${DOWNLOAD_DIR}" && -d "${DOWNLOAD_DIR}" ]]; then
    rm -rf "${DOWNLOAD_DIR}"
  fi
}

trap cleanup EXIT

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [options]

Install the multi-agent pack for Claude Code and/or Codex.

Options:
  --target <claude|codex|all>      Installation target. Default: all
  --scope <user|project|local>     Installation scope. Default: project
  --activate-coordinator <yes|no>  For Claude plugin installs, ship settings.json with coordinator as default. Default: no
  --project-dir <path>             Target project directory for project/local installs. Default: current working directory
  --dry-run                        Print actions without writing files
  --force                          Replace conflicting marketplace/plugin installs when needed
  --interactive                    Force interactive guided mode
  --help                           Show this help

Notes:
  - Running the script without arguments starts the interactive installer when a terminal is available.
  - Claude Code plugin installs support user, project, and local scopes.
  - Codex subagent installs currently support user and project scopes only.
  - Remote installs use the built-in GitHub source defined in this script.

Examples:
  ${SCRIPT_NAME}
  ${SCRIPT_NAME} --target all --scope project --project-dir /path/to/project
  ${SCRIPT_NAME} --target claude --scope local --activate-coordinator yes
  ${SCRIPT_NAME} --target codex --scope user
  curl -fsSL <raw-install-script-url> | bash -s --
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

tty_input_available() {
  [[ -r /dev/tty && -w /dev/tty ]]
}

resolve_abs_path() {
  local path="$1"
  node -e 'const path=require("path"); console.log(path.resolve(process.argv[1]));' "$path"
}

cache_root() {
  printf '%s\n' "${XDG_CACHE_HOME:-${HOME}/.cache}/cc-multi-agent"
}

detect_script_root() {
  local script_path=""
  local script_dir

  if [[ ${#BASH_SOURCE[@]} -gt 0 ]]; then
    script_path="${BASH_SOURCE[0]:-}"
  fi

  if [[ -z "${script_path}" || "${script_path}" == "-" || "${script_path}" == "bash" ]]; then
    script_path="${0:-}"
  fi

  if [[ -z "${script_path}" || "${script_path}" == "-" || "${script_path}" == "bash" ]]; then
    return 1
  fi

  script_dir="$(cd "$(dirname "${script_path}")" && pwd)"
  if [[ -d "${script_dir}/agents" && -d "${script_dir}/.claude-plugin" ]]; then
    printf '%s\n' "${script_dir}"
    return 0
  fi
  return 1
}

download_github_repo() {
  require_cmd curl
  require_cmd tar

  DOWNLOAD_DIR="$(mktemp -d)"
  local archive_path="${DOWNLOAD_DIR}/repo.tar.gz"
  local url="https://codeload.github.com/${DEFAULT_REMOTE_REPO}/tar.gz/${DEFAULT_REMOTE_REF}"

  [[ -n "${DEFAULT_REMOTE_REPO}" ]] || die "DEFAULT_REMOTE_REPO is not configured in this script."
  [[ -n "${DEFAULT_REMOTE_REF}" ]] || die "DEFAULT_REMOTE_REF is not configured in this script."

  printf '%s\n' "Downloading ${DEFAULT_REMOTE_REPO}@${DEFAULT_REMOTE_REF}" >&2
  curl -fsSL "${url}" -o "${archive_path}"
  tar -xzf "${archive_path}" -C "${DOWNLOAD_DIR}"

  local extracted
  extracted="$(find "${DOWNLOAD_DIR}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  [[ -n "${extracted}" ]] || die "Failed to extract repository archive from ${url}"
  printf '%s\n' "${extracted}"
}

discover_source_root() {
  local root=""

  if root="$(detect_script_root)"; then
    DISCOVERED_SOURCE_KIND="local"
    DISCOVERED_SOURCE_ROOT="${root}"
    return 0
  fi

  DISCOVERED_SOURCE_KIND="github"

  if [[ "${TARGET}" == "claude" ]]; then
    DISCOVERED_SOURCE_ROOT=""
    return 0
  fi

  root="$(download_github_repo)"
  [[ -d "${root}/agents" ]] || die "Source root does not contain agents/: ${root}"
  [[ -d "${root}/.claude-plugin" ]] || die "Source root does not contain .claude-plugin/: ${root}"
  DISCOVERED_SOURCE_ROOT="${root}"
}

ensure_project_dir() {
  local project_dir

  if [[ -n "${TARGET_PROJECT_DIR}" ]]; then
    project_dir="$(resolve_abs_path "${TARGET_PROJECT_DIR}")"
  else
    project_dir="$(pwd)"
  fi

  if [[ "${SCOPE}" != "user" && ! -d "${project_dir}" ]]; then
    die "Project directory does not exist: ${project_dir}"
  fi

  printf '%s\n' "${project_dir}"
}

yaml_frontmatter_to_json() {
  local agent_file="$1"
  node - "${agent_file}" <<'NODE'
const fs = require('fs');
const file = process.argv[2];
const content = fs.readFileSync(file, 'utf8');
if (!content.startsWith('---\n')) {
  throw new Error(`Missing YAML frontmatter in ${file}`);
}
const end = content.indexOf('\n---\n', 4);
if (end === -1) {
  throw new Error(`Could not find frontmatter terminator in ${file}`);
}
const frontmatter = content.slice(4, end).trim();
const body = content.slice(end + 5).trim();
const data = {};
for (const rawLine of frontmatter.split(/\r?\n/)) {
  const line = rawLine.trim();
  if (!line || line.startsWith('#')) continue;
  const idx = line.indexOf(':');
  if (idx === -1) {
    throw new Error(`Invalid frontmatter line in ${file}: ${rawLine}`);
  }
  const key = line.slice(0, idx).trim();
  let value = line.slice(idx + 1).trim();
  if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
    value = value.slice(1, -1);
  }
  data[key] = value;
}
if (!data.name || !data.description) {
  throw new Error(`Frontmatter in ${file} must include name and description`);
}
data.body = body;
console.log(JSON.stringify(data));
NODE
}

generate_codex_toml() {
  local agent_file="$1"
  local json
  json="$(yaml_frontmatter_to_json "${agent_file}")"

  node - "${json}" <<'NODE'
const agent = JSON.parse(process.argv[2]);
let out = '';
const append = (line = '') => {
  out += `${line}\n`;
};
append(`name = ${JSON.stringify(agent.name)}`);
append(`description = ${JSON.stringify(agent.description)}`);
append('developer_instructions = """');
append(agent.body);
append('"""');
process.stdout.write(out);
NODE
}

list_agent_files() {
  local source_root="$1"
  find "${source_root}/agents" -maxdepth 1 -type f -name '*.md' | sort
}

managed_codex_block() {
  cat <<EOF
${MANAGED_BEGIN}
## Installed Subagent Routing Policy

Use the installed custom agents with the following defaults:

- Default path: \`implementer -> code-simplifier -> reviewer\`
- Use \`architect\` for cross-module, API/schema/contract, migration, compatibility, or multi-option design work
- Use \`researcher\` when evidence, code context, or latest documentation is missing
- Use \`frontend-reviewer\` for visible UI work, rendered page audits, or frontend validation against style, accessibility, responsiveness, and performance expectations
- Use \`reviewer\` for medium- and high-risk work, public interface changes, and cases with incomplete validation
- Use \`coordinator\` when the task benefits from delegation and routing across these specialists

Role boundaries:

- \`coordinator\` decides routing and owns the final answer
- \`implementer\` makes the actual code change
- \`code-simplifier\` cleans up recently changed code without changing behavior
- \`reviewer\` focuses on bugs, regressions, validation gaps, and maintainability risks
- \`architect\` does design work only and should not take over routine implementation
- \`researcher\` gathers evidence and context without silently broadening task scope
- \`frontend-reviewer\` evaluates the rendered UI for style fidelity, visual quality, accessibility, responsiveness, interaction quality, and performance evidence
${MANAGED_END}
EOF
}

write_managed_block() {
  local target_file="$1"
  local existing=""
  local managed
  managed="$(managed_codex_block)"

  if [[ -f "${target_file}" ]]; then
    existing="$(cat "${target_file}")"
  fi

  local rendered
  rendered="$(node - "${target_file}" "${existing}" "${managed}" "${MANAGED_BEGIN}" "${MANAGED_END}" <<'NODE'
const [, , filePath, existing, managed, begin, end] = process.argv;
let result = existing || '';
const blockRegex = new RegExp(`${begin.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}[\\s\\S]*?${end.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`, 'm');
if (blockRegex.test(result)) {
  result = result.replace(blockRegex, managed);
} else if (result.trim().length === 0) {
  result = managed;
} else {
  result = `${result.replace(/\s+$/, '')}\n\n${managed}`;
}
process.stdout.write(result.endsWith('\n') ? result : `${result}\n`);
NODE
)"

  if [[ "${DRY_RUN}" == "yes" ]]; then
    log "  - would update managed block in ${target_file}"
    return 0
  fi

  mkdir -p "$(dirname "${target_file}")"
  printf '%s\n' "${rendered}" > "${target_file}"
}

install_codex_agents() {
  local source_root="$1"
  local codex_agent_dir="$2"
  local codex_agents_md="$3"
  local agent_file
  local basename
  local toml_content

  log "Installing Codex subagents into ${codex_agent_dir}"

  if [[ "${DRY_RUN}" != "yes" ]]; then
    mkdir -p "${codex_agent_dir}"
  fi

  while read -r agent_file; do
    basename="$(basename "${agent_file}" .md)"
    toml_content="$(generate_codex_toml "${agent_file}")"
    if [[ "${DRY_RUN}" == "yes" ]]; then
      log "  - would write ${codex_agent_dir}/${basename}.toml"
    else
      printf '%s' "${toml_content}" > "${codex_agent_dir}/${basename}.toml"
    fi
  done < <(list_agent_files "${source_root}")

  write_managed_block "${codex_agents_md}"
}

copy_source_artifacts() {
  local source_root="$1"
  local destination="$2"
  local doc_file

  rm -rf "${destination}"
  mkdir -p "${destination}"

  cp -R "${source_root}/agents" "${destination}/agents"
  cp -R "${source_root}/.claude-plugin" "${destination}/.claude-plugin"

  for doc_file in AGENTS.md AGENTS.zh-CN.md PR_REVIEWER.md PR_REVIEWER.zh-CN.md; do
    if [[ -f "${source_root}/${doc_file}" ]]; then
      cp "${source_root}/${doc_file}" "${destination}/${doc_file}"
    fi
  done
}

prepare_claude_plugin_source() {
  local source_root="$1"
  local plugin_source_dir

  plugin_source_dir="$(cache_root)/claude-plugin-source"

  if [[ "${DRY_RUN}" != "yes" ]]; then
    mkdir -p "$(dirname "${plugin_source_dir}")"
    copy_source_artifacts "${source_root}" "${plugin_source_dir}"
  fi

  printf '%s\n' "${plugin_source_dir}"
}

run_claude_cli() {
  (
    cd "${WORK_DIR}"
    claude "$@"
  )
}

claude_settings_file() {
  case "${SCOPE}" in
    user)
      printf '%s\n' "${HOME}/.claude/settings.json"
      ;;
    project)
      printf '%s\n' "${WORK_DIR}/.claude/settings.json"
      ;;
    local)
      printf '%s\n' "${WORK_DIR}/.claude/settings.local.json"
      ;;
    *)
      die "Unsupported Claude settings scope: ${SCOPE}"
      ;;
  esac
}

write_claude_marketplace_setting() {
  local settings_file="$1"
  local source_kind="$2"
  local source_value="$3"
  local existing=""
  local rendered=""

  if [[ -f "${settings_file}" ]]; then
    existing="$(cat "${settings_file}")"
  fi

  rendered="$(node - "${existing}" "${settings_file}" "${DEFAULT_MARKETPLACE_NAME}" "${source_kind}" "${source_value}" <<'NODE'
const [, , existing, settingsFile, marketplaceName, sourceKind, sourceValue] = process.argv;
let data = {};
if (existing && existing.trim().length > 0) {
  try {
    data = JSON.parse(existing);
  } catch (error) {
    throw new Error(`Failed to parse ${settingsFile}: ${error.message}`);
  }
}
if (!data.extraKnownMarketplaces || typeof data.extraKnownMarketplaces !== 'object' || Array.isArray(data.extraKnownMarketplaces)) {
  data.extraKnownMarketplaces = {};
}
const source = { source: sourceKind };
if (sourceKind === 'github') {
  source.repo = sourceValue;
} else {
  source.path = sourceValue;
}
data.extraKnownMarketplaces[marketplaceName] = { source };
process.stdout.write(`${JSON.stringify(data, null, 2)}\n`);
NODE
)"

  if [[ "${DRY_RUN}" == "yes" ]]; then
    log "  - would declare marketplace ${DEFAULT_MARKETPLACE_NAME} in ${settings_file} as ${source_kind}:${source_value}"
    return 0
  fi

  mkdir -p "$(dirname "${settings_file}")"
  printf '%s' "${rendered}" > "${settings_file}"
}

write_claude_default_agent_setting() {
  local settings_file="$1"
  local agent_ref="$2"
  local existing=""
  local rendered=""

  if [[ -f "${settings_file}" ]]; then
    existing="$(cat "${settings_file}")"
  fi

  rendered="$(node - "${existing}" "${agent_ref}" "${settings_file}" <<'NODE'
const [, , existing, agentRef, settingsFile] = process.argv;
let data = {};
if (existing && existing.trim().length > 0) {
  try {
    data = JSON.parse(existing);
  } catch (error) {
    throw new Error(`Failed to parse ${settingsFile}: ${error.message}`);
  }
}
data.agent = agentRef;
process.stdout.write(`${JSON.stringify(data, null, 2)}\n`);
NODE
)"

  if [[ "${DRY_RUN}" == "yes" ]]; then
    log "  - would set default Claude agent in ${settings_file} to ${agent_ref}"
    return 0
  fi

  mkdir -p "$(dirname "${settings_file}")"
  printf '%s' "${rendered}" > "${settings_file}"
}

claude_plugin_installed() {
  local plugin_ref="$1"
  local scope="$2"
  local project_dir="$3"
  run_claude_cli plugin list --json --available | jq -e \
    --arg plugin_ref "${plugin_ref}" \
    --arg scope "${scope}" \
    --arg project_dir "${project_dir}" '
      any(.installed[]?; .id == $plugin_ref and .scope == $scope and (
        $scope == "user" or ((.projectPath // $project_dir) == $project_dir)
      ))
    ' >/dev/null
}

install_claude_plugin() {
  local source_root="$1"
  local plugin_source_dir=""
  local plugin_ref="${DEFAULT_PLUGIN_NAME}@${DEFAULT_MARKETPLACE_NAME}"
  local desired_marketplace_source=""
  local desired_marketplace_source_kind=""
  local default_agent_ref="${DEFAULT_PLUGIN_NAME}:coordinator"
  local settings_file=""

  require_cmd claude
  require_cmd jq
  settings_file="$(claude_settings_file)"

  if [[ "${DISCOVERED_SOURCE_KIND}" == "github" ]]; then
    desired_marketplace_source_kind="github"
    desired_marketplace_source="${DEFAULT_REMOTE_REPO}"
    log "Preparing Claude Code marketplace source from GitHub repo ${desired_marketplace_source}"
  else
    desired_marketplace_source_kind="directory"
    plugin_source_dir="$(prepare_claude_plugin_source "${source_root}")"
    desired_marketplace_source="${plugin_source_dir}"
    log "Preparing Claude Code plugin source at ${plugin_source_dir}"
  fi

  if [[ "${DRY_RUN}" == "yes" ]]; then
    if [[ "${desired_marketplace_source_kind}" == "directory" ]]; then
      log "  - would run: claude plugin validate ${plugin_source_dir}"
    fi
    write_claude_marketplace_setting "${settings_file}" "${desired_marketplace_source_kind}" "${desired_marketplace_source}"
    log "  - would install ${plugin_ref} with scope ${SCOPE}"
    if [[ "${ACTIVATE_COORDINATOR}" == "yes" ]]; then
      write_claude_default_agent_setting "${settings_file}" "${default_agent_ref}"
    fi
    return 0
  fi

  if [[ "${desired_marketplace_source_kind}" == "directory" ]]; then
    run_claude_cli plugin validate "${plugin_source_dir}" >/dev/null
  fi

  run_claude_cli plugin marketplace add --scope "${SCOPE}" "${desired_marketplace_source}" >/dev/null
  run_claude_cli plugin marketplace update "${DEFAULT_MARKETPLACE_NAME}" >/dev/null
  write_claude_marketplace_setting "${settings_file}" "${desired_marketplace_source_kind}" "${desired_marketplace_source}"

  if claude_plugin_installed "${plugin_ref}" "${SCOPE}" "${WORK_DIR}"; then
    if [[ "${FORCE}" != "yes" ]]; then
      warn "Claude plugin ${plugin_ref} is already installed for scope ${SCOPE}. Re-run with --force to reinstall it."
    else
      run_claude_cli plugin uninstall --scope "${SCOPE}" "${plugin_ref}" >/dev/null || true
      run_claude_cli plugin install --scope "${SCOPE}" "${plugin_ref}" >/dev/null
    fi
  else
    run_claude_cli plugin install --scope "${SCOPE}" "${plugin_ref}" >/dev/null
  fi

  if [[ "${ACTIVATE_COORDINATOR}" == "yes" ]]; then
    settings_file="$(claude_settings_file)"
    write_claude_default_agent_setting "${settings_file}" "${default_agent_ref}"
  fi
}

print_summary() {
  log ""
  log "Install summary"
  log "  version: ${VERSION}"
  log "  target: ${TARGET}"
  log "  scope: ${SCOPE}"
  log "  activate coordinator: ${ACTIVATE_COORDINATOR}"
  if [[ -n "${DISCOVERED_SOURCE_KIND}" ]]; then
    log "  source kind: ${DISCOVERED_SOURCE_KIND}"
    if [[ "${DISCOVERED_SOURCE_KIND}" == "github" ]]; then
      log "  source repo: ${DEFAULT_REMOTE_REPO}@${DEFAULT_REMOTE_REF}"
    fi
  fi
  if [[ -n "${TARGET_PROJECT_DIR}" ]]; then
    log "  project dir: ${TARGET_PROJECT_DIR}"
  fi
  log "  dry run: ${DRY_RUN}"
}

parse_args() {
  if [[ $# -gt 0 ]]; then
    HAD_ARGS="yes"
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target)
        TARGET="$2"
        shift 2
        ;;
      --scope)
        SCOPE="$2"
        shift 2
        ;;
      --activate-coordinator)
        ACTIVATE_COORDINATOR="$2"
        shift 2
        ;;
      --project-dir)
        TARGET_PROJECT_DIR="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN="yes"
        shift
        ;;
      --force)
        FORCE="yes"
        shift
        ;;
      --interactive)
        INTERACTIVE="yes"
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

read_with_default() {
  local prompt="$1"
  local default_value="$2"
  local result=""
  if [[ -t 0 ]]; then
    read -r -p "${prompt} [${default_value}]: " result
  elif tty_input_available; then
    read -r -p "${prompt} [${default_value}]: " result < /dev/tty
  fi
  if [[ -z "${result}" ]]; then
    printf '%s\n' "${default_value}"
  else
    printf '%s\n' "${result}"
  fi
}

prompt_interactively() {
  [[ -t 0 ]] || tty_input_available || return 0

  log ""
  log "Interactive install guide"

  TARGET="$(read_with_default "Target (claude/codex/all)" "${TARGET}")"
  SCOPE="$(read_with_default "Scope (user/project/local)" "${SCOPE}")"

  if [[ "${TARGET}" == "claude" || "${TARGET}" == "all" ]]; then
    ACTIVATE_COORDINATOR="$(read_with_default "Activate coordinator by default for Claude? (yes/no)" "${ACTIVATE_COORDINATOR}")"
  fi

  if [[ "${SCOPE}" != "user" ]]; then
    TARGET_PROJECT_DIR="$(read_with_default "Project directory" "${TARGET_PROJECT_DIR:-$(pwd)}")"
  fi

  log ""
}

validate_args() {
  case "${TARGET}" in
    claude|codex|all) ;;
    *) die "--target must be claude, codex, or all" ;;
  esac

  case "${SCOPE}" in
    user|project|local) ;;
    *) die "--scope must be user, project, or local" ;;
  esac

  case "${ACTIVATE_COORDINATOR}" in
    yes|no) ;;
    *) die "--activate-coordinator must be yes or no" ;;
  esac

  if [[ "${SCOPE}" == "local" && ("${TARGET}" == "codex" || "${TARGET}" == "all") ]]; then
    die "Codex subagents do not currently support --scope local. Use --scope user or --scope project instead."
  fi
}

main() {
  parse_args "$@"
  if [[ "${HAD_ARGS}" == "no" || "${INTERACTIVE}" == "yes" ]]; then
    prompt_interactively
  fi
  validate_args

  require_cmd node

  local source_root
  local project_dir
  local codex_agent_dir=""
  local codex_agents_md=""

  discover_source_root
  source_root="${DISCOVERED_SOURCE_ROOT}"
  project_dir="$(ensure_project_dir)"
  WORK_DIR="${project_dir}"

  print_summary

  if [[ "${TARGET}" == "claude" || "${TARGET}" == "all" ]]; then
    install_claude_plugin "${source_root}"
  fi

  if [[ "${TARGET}" == "codex" || "${TARGET}" == "all" ]]; then
    if [[ "${SCOPE}" == "user" ]]; then
      codex_agent_dir="${HOME}/.codex/agents"
      codex_agents_md="${HOME}/.codex/AGENTS.md"
    else
      codex_agent_dir="${project_dir}/.codex/agents"
      codex_agents_md="${project_dir}/AGENTS.md"
    fi
    install_codex_agents "${source_root}" "${codex_agent_dir}" "${codex_agents_md}"
  fi

  log ""
  if [[ "${DRY_RUN}" == "yes" ]]; then
    log "Dry run completed."
  else
    log "Installation completed."
  fi
}

main "$@"
