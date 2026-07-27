#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
app_root="$(cd -- "${script_dir}/.." && pwd)"
server_root="${ROAMSTORY_SERVER_ROOT:-$(cd -- "${app_root}/../roamstory-server" && pwd)}"
environment_file="${server_root}/docker-compose/env/stage.env"
local_configuration="${app_root}/Config/Authentication.local.xcconfig"

if [[ ! -f "${environment_file}" ]]; then
    echo "Missing server stage environment: ${environment_file}" >&2
    echo "Set ROAMSTORY_SERVER_ROOT if roamstory-server is not next to the app repository." >&2
    exit 1
fi

read_environment_property() {
    local property_name="$1"
    local line
    local property_value=""

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == "${property_name}="* ]]; then
            property_value="${line#*=}"
        fi
    done < "${environment_file}"
    printf '%s' "${property_value}"
}

read_local_configuration_property() {
    local property_name="$1"
    local line
    local property_value=""

    [[ -f "${local_configuration}" ]] || return
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == "${property_name} = "* ]]; then
            property_value="${line#"${property_name} = "}"
        fi
    done < "${local_configuration}"
    printf '%s' "${property_value}"
}

write_environment_property() {
    local property_name="$1"
    local property_value="$2"
    local temporary_file
    local line
    local replaced=false

    temporary_file="$(mktemp "${environment_file}.tmp.XXXXXX")"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" == "${property_name}="* ]]; then
            if [[ "${replaced}" == false ]]; then
                printf '%s=%s\n' "${property_name}" "${property_value}" >> "${temporary_file}"
                replaced=true
            fi
        else
            printf '%s\n' "${line}" >> "${temporary_file}"
        fi
    done < "${environment_file}"

    if [[ "${replaced}" == false ]]; then
        printf '%s=%s\n' "${property_name}" "${property_value}" >> "${temporary_file}"
    fi

    chmod 600 "${temporary_file}"
    mv "${temporary_file}" "${environment_file}"
}

prompt_for_property() {
    local property_name="$1"
    local prompt_label="$2"
    local retrieval_hint="$3"
    local property_value
    local local_property_value

    property_value="$(read_environment_property "${property_name}")"
    if [[ -n "${property_value}" && "${property_value}" != replace-with-* ]]; then
        printf '%s' "${property_value}"
        return
    fi

    local_property_value="$(read_local_configuration_property "${property_name}")"
    if [[ -n "${local_property_value}" && "${local_property_value}" != replace-with-* ]]; then
        write_environment_property "${property_name}" "${local_property_value}"
        printf '%s' "${local_property_value}"
        return
    fi

    echo "Missing ${property_name}." >&2
    echo "${retrieval_hint}" >&2
    if [[ ! -t 0 ]]; then
        echo "Run this script in an interactive terminal or add the value to ${environment_file}." >&2
        exit 1
    fi

    while [[ -z "${property_value}" || "${property_value}" == replace-with-* ]]; do
        IFS= read -r -p "${prompt_label}: " property_value
        if [[ -z "${property_value}" || "${property_value}" == replace-with-* ]]; then
            echo "A real value is required." >&2
        fi
    done

    write_environment_property "${property_name}" "${property_value}"
    printf '%s' "${property_value}"
}

google_web_client_id="$(prompt_for_property \
    "GOOGLE_WEB_CLIENT_ID" \
    "Google Web OAuth client ID" \
    "Use Google Auth Platform > Clients > RoamStory Web (Web application), with https://roamstory.infiz.com registered as an Authorized JavaScript origin.")"
google_ios_client_id="$(prompt_for_property \
    "GOOGLE_IOS_CLIENT_ID" \
    "Google iOS OAuth client ID" \
    "Create or open the iOS OAuth client for bundle ID com.infiz.roamstory.")"

google_reversed_client_id="$(read_environment_property "GOOGLE_REVERSED_CLIENT_ID")"
if [[ -z "${google_reversed_client_id}" || "${google_reversed_client_id}" == replace-with-* ]]; then
    if [[ "${google_ios_client_id}" != *.apps.googleusercontent.com ]]; then
        echo "Cannot derive the reversed client ID because GOOGLE_IOS_CLIENT_ID has an unexpected format." >&2
        exit 1
    fi
    google_reversed_client_id="com.googleusercontent.apps.${google_ios_client_id%.apps.googleusercontent.com}"
    write_environment_property "GOOGLE_REVERSED_CLIENT_ID" "${google_reversed_client_id}"
fi

facebook_app_id="$(prompt_for_property \
    "FACEBOOK_APP_ID" \
    "Meta App ID" \
    "Use Meta for Developers > RoamStory > App settings > Basic > App ID.")"
facebook_client_token="$(prompt_for_property \
    "FACEBOOK_CLIENT_TOKEN" \
    "Meta Client Token" \
    "Use Meta for Developers > RoamStory > App settings > Advanced > Security > Client token. Do not enter the App Secret.")"

temporary_configuration="$(mktemp "${local_configuration}.tmp.XXXXXX")"
{
    printf '// Generated from %s by scripts/configure_stage_auth.sh.\n' "${environment_file}"
    printf 'GOOGLE_IOS_CLIENT_ID = %s\n' "${google_ios_client_id}"
    printf 'GOOGLE_REVERSED_CLIENT_ID = %s\n' "${google_reversed_client_id}"
    printf 'GOOGLE_WEB_CLIENT_ID = %s\n' "${google_web_client_id}"
    printf 'FACEBOOK_APP_ID = %s\n' "${facebook_app_id}"
    printf 'FACEBOOK_CLIENT_TOKEN = %s\n' "${facebook_client_token}"
} > "${temporary_configuration}"
chmod 600 "${temporary_configuration}"
mv "${temporary_configuration}" "${local_configuration}"

echo
echo "Generated ${local_configuration}."
echo "Clean the Xcode build folder, delete the installed app, and run RoamStory again."
