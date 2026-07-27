#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "${script_dir}/../.." && pwd)"
project_file="${repository_root}/RoamStory.xcodeproj"
resolved_file="${project_file}/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
backup_dir=""

restore_resolved_file() {
    if [[ -n "${backup_dir}" && -f "${backup_dir}/Package.resolved" ]]; then
        echo "Dependency upgrade failed; restoring the previous Package.resolved." >&2
        mkdir -p -- "$(dirname -- "${resolved_file}")"
        mv -- "${backup_dir}/Package.resolved" "${resolved_file}"
    fi
    if [[ -n "${backup_dir}" && -d "${backup_dir}" ]]; then
        rmdir -- "${backup_dir}" 2>/dev/null || true
    fi
}

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This script requires macOS because RoamStory dependencies are managed by Xcode." >&2
    exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "xcodebuild is unavailable. Install Xcode and select it with xcode-select." >&2
    exit 1
fi

cd "${repository_root}"

# Xcode keeps compatible package versions pinned in Package.resolved. Moving
# the lock file aside forces a fresh resolution while preserving it for
# automatic recovery if resolution or validation fails.
if [[ -f "${resolved_file}" ]]; then
    backup_dir="$(mktemp -d "${TMPDIR:-/tmp}/roamstory-package-upgrade.XXXXXX")"
    mv -- "${resolved_file}" "${backup_dir}/Package.resolved"
fi
trap restore_resolved_file ERR INT TERM

echo "Resolving the latest Swift package versions allowed by the Xcode project..."
xcodebuild \
    -resolvePackageDependencies \
    -project "${project_file}" \
    -scheme RoamStory

if [[ ! -f "${resolved_file}" ]]; then
    echo "Xcode did not create ${resolved_file}." >&2
    exit 1
fi

echo "Building RoamStory with the upgraded dependencies..."
"${repository_root}/scripts/pre_commit/build_ios.sh"

trap - ERR INT TERM
if [[ -n "${backup_dir}" ]]; then
    rm -f -- "${backup_dir}/Package.resolved"
    rmdir -- "${backup_dir}"
fi

echo
echo "Swift package dependency upgrade completed."
echo "Review Package.resolved and build changes before committing."
echo "Major-version upgrades still require updating package constraints in Xcode."
