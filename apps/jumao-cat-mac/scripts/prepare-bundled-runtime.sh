#!/usr/bin/env bash
set -euo pipefail

readonly NODE_VERSION="24.18.0"
readonly NODE_BASE_URL="https://nodejs.org/dist/v${NODE_VERSION}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$(cd "${script_dir}/.." && pwd)"
repository_root="$(cd "${app_dir}/../.." && pwd)"
runtime_dir="${app_dir}/Resources/BundledRuntime"
runtime_files="${app_dir}/runtime-files.txt"
cache_dir="${JUMAO_RUNTIME_CACHE_DIR:-${HOME}/Library/Caches/JumaoCat/Node/v${NODE_VERSION}}"
checksum_file="${cache_dir}/SHASUMS256.txt"
temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/jumao-cat-runtime.XXXXXX")"

requested_architecture="current"
architecture_was_supplied=false
clean=false
verify_only=false

cleanup() {
  rm -rf "${temporary_dir}"
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage: prepare-bundled-runtime.sh [--arch arm64|x86_64|current|all] [--clean] [--verify-only]
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "缺少必需命令：$1" >&2
    exit 1
  }
}

read_runtime_files() {
  while IFS= read -r relative_path || [[ -n "${relative_path}" ]]; do
    [[ -z "${relative_path}" || "${relative_path}" == \#* ]] && continue
    case "${relative_path}" in
      /*|*".."*)
        echo "runtime-files.txt 包含不安全路径：${relative_path}" >&2
        exit 1
        ;;
    esac
    [[ -e "${repository_root}/${relative_path}" ]] || {
      echo "runtime-files.txt 引用的资源不存在：${relative_path}" >&2
      exit 1
    }
    printf '%s\n' "${relative_path}"
  done < "${runtime_files}"
}

validate_runtime_files() {
  [[ -f "${runtime_files}" ]] || {
    echo "缺少资源清单：${runtime_files}" >&2
    exit 1
  }
  [[ -n "$(read_runtime_files)" ]] || {
    echo "runtime-files.txt 不能为空。" >&2
    exit 1
  }
}

host_architecture() {
  case "$(uname -m)" in
    arm64|x86_64) printf '%s\n' "$(uname -m)" ;;
    *)
      echo "不支持当前 Mac 架构：$(uname -m)" >&2
      exit 1
      ;;
  esac
}

resolve_architecture() {
  case "$1" in
    current) host_architecture ;;
    arm64|x86_64) printf '%s\n' "$1" ;;
    *)
      echo "不支持的 --arch：$1" >&2
      exit 1
      ;;
  esac
}

node_archive_architecture() {
  case "$1" in
    arm64) printf 'arm64\n' ;;
    x86_64) printf 'x64\n' ;;
  esac
}

download_checksums_if_needed() {
  mkdir -p "${cache_dir}"
  if [[ ! -s "${checksum_file}" ]]; then
    curl --fail --location --retry 3 --output "${temporary_dir}/SHASUMS256.txt" "${NODE_BASE_URL}/SHASUMS256.txt"
    mv "${temporary_dir}/SHASUMS256.txt" "${checksum_file}"
  fi
}

verify_archive() {
  local archive_name="$1"
  local archive_path="$2"
  local expected_checksum
  local actual_checksum

  expected_checksum="$(awk -v archive="${archive_name}" '$2 == archive { print $1; exit }' "${checksum_file}")"
  [[ "${expected_checksum}" =~ ^[0-9a-f]{64}$ ]] || {
    echo "官方 SHASUMS256.txt 中缺少 ${archive_name} 的 SHA-256。" >&2
    exit 1
  }

  actual_checksum="$(shasum -a 256 "${archive_path}" | awk '{ print $1 }')"
  [[ "${actual_checksum}" == "${expected_checksum}" ]] || {
    echo "SHA-256 校验失败：${archive_name}" >&2
    exit 1
  }
}

download_archive_if_needed() {
  local archive_name="$1"
  local archive_path="${cache_dir}/${archive_name}"
  local temporary_archive="${temporary_dir}/${archive_name}"

  if [[ -f "${archive_path}" ]]; then
    verify_archive "${archive_name}" "${archive_path}"
    return
  fi

  curl --fail --location --retry 3 --output "${temporary_archive}" "${NODE_BASE_URL}/${archive_name}"
  verify_archive "${archive_name}" "${temporary_archive}"
  mv "${temporary_archive}" "${archive_path}"
}

remove_runtime() {
  local target_dir="$1"
  if [[ -e "${target_dir}" ]]; then
    chmod -R u+w "${target_dir}"
    rm -rf "${target_dir}"
  fi
}

copy_jumao_resources() {
  local target_dir="$1"
  local relative_path

  mkdir -p "${target_dir}/jumao"
  while IFS= read -r relative_path; do
    mkdir -p "$(dirname "${target_dir}/jumao/${relative_path}")"
    cp -R "${repository_root}/${relative_path}" "${target_dir}/jumao/${relative_path}"
  done < <(read_runtime_files)
}

jumao_version() {
  local version
  version="$(sed -nE 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "${repository_root}/package.json" | head -n 1)"
  [[ -n "${version}" ]] || {
    echo "无法从 package.json 读取 Jumao 版本。" >&2
    exit 1
  }
  printf '%s\n' "${version}"
}

write_manifest() {
  local target_dir="$1"
  local architecture="$2"

  printf '{\n  "schemaVersion": 1,\n  "nodeVersion": "%s",\n  "jumaoVersion": "%s",\n  "architecture": "%s"\n}\n' \
    "${NODE_VERSION}" "$(jumao_version)" "${architecture}" > "${target_dir}/runtime-manifest.json"
  chmod 0444 "${target_dir}/runtime-manifest.json"
}

set_permissions() {
  local target_dir="$1"

  chmod 0555 "${target_dir}/node/node"
  find "${target_dir}/jumao" -type d -exec chmod 0755 {} +
  find "${target_dir}/jumao" -type f -exec chmod 0644 {} +
  chmod 0444 "${target_dir}/jumao/LICENSE"
  chmod 0444 "${target_dir}/ThirdPartyLicenses/Jumao-LICENSE" "${target_dir}/ThirdPartyLicenses/Node-LICENSE"
}

prepare_runtime() {
  local target_dir="$1"
  local architecture="$2"
  local archive_architecture
  local archive_name
  local extracted_dir
  local source_node
  local source_license

  validate_runtime_files
  download_checksums_if_needed
  archive_architecture="$(node_archive_architecture "${architecture}")"
  archive_name="node-v${NODE_VERSION}-darwin-${archive_architecture}.tar.gz"
  download_archive_if_needed "${archive_name}"

  extracted_dir="${temporary_dir}/node-v${NODE_VERSION}-darwin-${archive_architecture}"
  tar -xzf "${cache_dir}/${archive_name}" -C "${temporary_dir}"
  source_node="${extracted_dir}/bin/node"
  source_license="${extracted_dir}/LICENSE"
  [[ -x "${source_node}" && -f "${source_license}" ]] || {
    echo "官方 Node 包缺少 node 或 LICENSE。" >&2
    exit 1
  }

  remove_runtime "${target_dir}"
  mkdir -p "${target_dir}/node" "${target_dir}/ThirdPartyLicenses"
  install -m 0555 "${source_node}" "${target_dir}/node/node"
  copy_jumao_resources "${target_dir}"
  install -m 0444 "${repository_root}/LICENSE" "${target_dir}/ThirdPartyLicenses/Jumao-LICENSE"
  install -m 0444 "${source_license}" "${target_dir}/ThirdPartyLicenses/Node-LICENSE"
  write_manifest "${target_dir}" "${architecture}"
  set_permissions "${target_dir}"
}

manifest_value() {
  local target_dir="$1"
  local key="$2"
  sed -nE "s/^[[:space:]]*\"${key}\"[[:space:]]*:[[:space:]]*(\"([^\"]+)\"|([0-9]+)).*/\2\3/p" "${target_dir}/runtime-manifest.json" | head -n 1
}

verify_mode() {
  local expected_mode="$1"
  local path="$2"
  local actual_mode

  actual_mode="$(stat -f '%Lp' "${path}")"
  [[ "${actual_mode}" == "${expected_mode}" ]] || {
    echo "权限不正确：${path}（期望 ${expected_mode}，实际 ${actual_mode}）" >&2
    exit 1
  }
}

verify_runtime() {
  local target_dir="$1"
  local architecture
  local expected_architecture
  local schema_path="${temporary_dir}/schema.json"
  local relative_path
  local file_path

  [[ -f "${target_dir}/runtime-manifest.json" ]] || {
    echo "缺少 runtime-manifest.json。" >&2
    exit 1
  }
  [[ -f "${target_dir}/node/node" ]] || {
    echo "缺少内置 node。" >&2
    exit 1
  }
  [[ "$(find "${target_dir}/node" -type f | wc -l | tr -d ' ')" == "1" ]] || {
    echo "node 目录必须只包含一个 node 二进制。" >&2
    exit 1
  }

  architecture="$(manifest_value "${target_dir}" architecture)"
  expected_architecture="$(resolve_architecture "${architecture}")"
  [[ "$(manifest_value "${target_dir}" schemaVersion)" == "1" ]] || {
    echo "runtime-manifest.json 的 schemaVersion 无效。" >&2
    exit 1
  }
  [[ "$(manifest_value "${target_dir}" nodeVersion)" == "${NODE_VERSION}" ]] || {
    echo "runtime-manifest.json 的 Node 版本无效。" >&2
    exit 1
  }
  [[ "$(manifest_value "${target_dir}" jumaoVersion)" == "$(jumao_version)" ]] || {
    echo "runtime-manifest.json 的 Jumao 版本无效。" >&2
    exit 1
  }
  [[ "${architecture}" == "${expected_architecture}" ]] || {
    echo "runtime-manifest.json 的 architecture 无效。" >&2
    exit 1
  }
  file "${target_dir}/node/node" | grep -Eq "Mach-O.*${architecture}" || {
    echo "内置 node 架构不匹配：${architecture}" >&2
    exit 1
  }

  verify_mode 555 "${target_dir}/node/node"
  verify_mode 444 "${target_dir}/ThirdPartyLicenses/Jumao-LICENSE"
  verify_mode 444 "${target_dir}/ThirdPartyLicenses/Node-LICENSE"
  while IFS= read -r relative_path; do
    [[ -e "${target_dir}/jumao/${relative_path}" ]] || {
      echo "缺少内置 Jumao 资源：${relative_path}" >&2
      exit 1
    }
  done < <(read_runtime_files)
  while IFS= read -r -d '' file_path; do
    verify_mode 644 "${file_path}"
  done < <(find "${target_dir}/jumao/bin" "${target_dir}/jumao/src" "${target_dir}/jumao/templates" -type f -print0)

  if [[ "${architecture}" != "$(host_architecture)" ]]; then
    echo "已验证 ${architecture} 文件结构、权限和 Mach-O 架构；当前机器不原生执行它。"
    return
  fi

  [[ "$("${target_dir}/node/node" --version)" == "v${NODE_VERSION}" ]] || {
    echo "内置 node 版本不匹配。" >&2
    exit 1
  }
  env -i PATH=/usr/bin:/bin HOME="${TMPDIR:-/tmp}" \
    "${target_dir}/node/node" "${target_dir}/jumao/bin/jumao.js" interview --schema > "${schema_path}"
  "${target_dir}/node/node" -e 'JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"))' "${schema_path}"
  grep -Eq '"schemaVersion"[[:space:]]*:[[:space:]]*2' "${schema_path}" || {
    echo "内置 CLI 没有输出预期 schemaVersion。" >&2
    exit 1
  }
  echo "已验证 ${architecture} 的内置 Node 和 CLI。"
}

require_command awk
require_command curl
require_command file
require_command find
require_command grep
require_command install
require_command mktemp
require_command sed
require_command shasum
require_command stat
require_command tar

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      [[ $# -ge 2 ]] || { usage >&2; exit 1; }
      requested_architecture="$2"
      architecture_was_supplied=true
      shift 2
      ;;
    --clean)
      clean=true
      shift
      ;;
    --verify-only)
      verify_only=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "${clean}" == true ]]; then
  remove_runtime "${runtime_dir}"
  if [[ "${architecture_was_supplied}" == false && "${verify_only}" == false ]]; then
    echo "已删除 ${runtime_dir}"
    exit 0
  fi
fi

if [[ "${verify_only}" == true ]]; then
  [[ "${requested_architecture}" != "all" ]] || {
    echo "--verify-only 只能验证正式 BundledRuntime。" >&2
    exit 1
  }
  verify_runtime "${runtime_dir}"
  exit 0
fi

if [[ "${requested_architecture}" == "all" ]]; then
  for architecture in arm64 x86_64; do
    target_dir="${temporary_dir}/all/${architecture}"
    prepare_runtime "${target_dir}" "${architecture}"
    verify_runtime "${target_dir}"
  done
  echo "已在临时目录验证 arm64 和 x86_64，不影响 ${runtime_dir}。"
  exit 0
fi

architecture="$(resolve_architecture "${requested_architecture}")"
prepare_runtime "${runtime_dir}" "${architecture}"
verify_runtime "${runtime_dir}"
echo "Bundled Jumao runtime prepared in ${runtime_dir} (${architecture})"
