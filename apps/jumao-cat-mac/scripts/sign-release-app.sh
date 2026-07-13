#!/usr/bin/env bash
set -euo pipefail

readonly TEAM_ID="L2TYJNDTJK"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$(cd "${script_dir}/.." && pwd)"
app_entitlements="${app_dir}/Signing/JumaoCat.entitlements"
node_entitlements="${app_dir}/Signing/BundledNode.entitlements"

usage() {
  echo "Usage: $(basename "$0") /path/to/JumaoCat.app" >&2
}

[[ $# -eq 1 ]] || {
  usage
  exit 1
}

app_path="$1"
[[ -d "${app_path}" && "${app_path}" == *.app ]] || {
  echo "待签名 App 不存在或不是 .app：${app_path}" >&2
  exit 1
}

for path in "${app_entitlements}" "${node_entitlements}" "${app_path}/Contents/Info.plist"; do
  [[ -f "${path}" ]] || {
    echo "缺少签名所需文件：${path}" >&2
    exit 1
  }
done

main_executable="$(find "${app_path}/Contents/MacOS" -maxdepth 1 -type f -perm -111 -print | head -n 1)"
main_executable_count="$(find "${app_path}/Contents/MacOS" -maxdepth 1 -type f -perm -111 | wc -l | tr -d ' ')"
[[ "${main_executable_count}" == "1" ]] || {
  echo "App 必须只有一个主程序：${app_path}/Contents/MacOS" >&2
  exit 1
}
node_executable="${app_path}/Contents/Resources/BundledRuntime/node/node"

for path in "${main_executable}" "${node_executable}"; do
  [[ -f "${path}" ]] || {
    echo "缺少待签名可执行文件：${path}" >&2
    exit 1
  }
done

for path in "${main_executable}" "${node_executable}"; do
  [[ "$(lipo -archs "${path}")" == "arm64" ]] || {
    echo "仅支持 arm64 发布产物：${path}" >&2
    exit 1
  }
done

certificate_matches="$(security find-identity -v -p codesigning | grep -E "\"Developer ID Application: .* \(${TEAM_ID}\)\"" || true)"
certificate_count="$(printf '%s\n' "${certificate_matches}" | awk 'NF { count += 1 } END { print count + 0 }')"
[[ "${certificate_count}" == "1" ]] || {
  echo "需要唯一有效的 Developer ID Application 证书（Team ID: ${TEAM_ID}），实际找到 ${certificate_count} 个。" >&2
  exit 1
}
certificate_identity="$(printf '%s\n' "${certificate_matches}" | sed -nE 's/^.*"([^"]+)".*$/\1/p')"
[[ -n "${certificate_identity}" ]] || {
  echo "无法读取 Developer ID Application 证书名称。" >&2
  exit 1
}

# 先签嵌套 Node，再签 App；禁止使用 --deep。
codesign --force --sign "${certificate_identity}" --timestamp --options runtime \
  --entitlements "${node_entitlements}" "${node_executable}"
codesign --force --sign "${certificate_identity}" --timestamp --options runtime \
  --entitlements "${app_entitlements}" "${app_path}"

codesign --verify --strict --verbose=4 "${app_path}"
codesign -d --verbose=4 "${node_executable}"
codesign -d --verbose=4 "${app_path}"
if ! spctl --assess --type execute --verbose=4 "${app_path}"; then
  echo "spctl 评估未通过；本轮未公证时出现 Unnotarized Developer ID 属于预期结果。" >&2
fi
