#!/usr/bin/env bash
set -euo pipefail

workflows_dir="${1:-.github/workflows}"
dynamic_expression="\${{"
status=0

if [[ ! -d "${workflows_dir}" ]]; then
    echo "::error title=Missing workflows directory::${workflows_dir} does not exist"
    exit 1
fi

declare -A seen=()

metadata_tmp="$(mktemp -d)"
trap 'rm -rf "${metadata_tmp}"' EXIT

curl_headers=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl_headers=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

extract_uses() {
    local workflow_file="$1"

    awk '
        /^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*/ {
            sub(/^[[:space:]]*-?[[:space:]]*uses:[[:space:]]*/, "")
            sub(/[[:space:]]*#.*/, "")
            gsub(/"/, "")
            gsub(/\047/, "")
            gsub(/[[:space:]]+$/, "")
            if ($0 != "") {
                print $0
            }
        }
    ' "${workflow_file}"
}

fetch_action_metadata() {
    local owner="$1"
    local repository="$2"
    local action_path="$3"
    local ref="$4"
    local destination="$5"
    local metadata_name
    local url

    for metadata_name in action.yml action.yaml; do
        if [[ -n "${action_path}" ]]; then
            url="https://raw.githubusercontent.com/${owner}/${repository}/${ref}/${action_path}/${metadata_name}"
        else
            url="https://raw.githubusercontent.com/${owner}/${repository}/${ref}/${metadata_name}"
        fi

        if curl -fsSL --retry 3 "${curl_headers[@]}" "${url}" -o "${destination}" 2>/dev/null; then
            return 0
        fi
    done

    return 1
}

read_runtime() {
    local metadata_file="$1"

    awk '
        /^[[:space:]]*using:[[:space:]]*/ {
            sub(/^[[:space:]]*using:[[:space:]]*/, "")
            sub(/[[:space:]]*#.*/, "")
            gsub(/"/, "")
            gsub(/\047/, "")
            gsub(/[[:space:]]/, "")
            print
            exit
        }
    ' "${metadata_file}" | tr '[:upper:]' '[:lower:]'
}

while IFS= read -r -d '' workflow_file; do
    while IFS= read -r uses_value; do
        if [[ "${uses_value}" == ./* || "${uses_value}" == docker://* ]]; then
            continue
        fi

        if [[ "${uses_value}" == *"${dynamic_expression}"* ]]; then
            echo "::error file=${workflow_file},title=Dynamic action reference::Cannot verify ${uses_value}"
            status=1
            continue
        fi

        if [[ -n "${seen[${uses_value}]:-}" ]]; then
            continue
        fi
        seen["${uses_value}"]=1

        if [[ ! "${uses_value}" =~ ^([^/@]+)/([^/@]+)(/[^@]+)?@(.+)$ ]]; then
            echo "::error file=${workflow_file},title=Unsupported action reference::Cannot parse ${uses_value}"
            status=1
            continue
        fi

        owner="${BASH_REMATCH[1]}"
        repository="${BASH_REMATCH[2]}"
        action_path="${BASH_REMATCH[3]:-}"
        action_path="${action_path#/}"
        ref="${BASH_REMATCH[4]}"
        metadata_file="${metadata_tmp}/${owner}-${repository}-${ref//[^A-Za-z0-9_.-]/_}-${action_path//[^A-Za-z0-9_.-]/_}.yml"

        if ! fetch_action_metadata "${owner}" "${repository}" "${action_path}" "${ref}" "${metadata_file}"; then
            echo "::error file=${workflow_file},title=Missing action metadata::Could not fetch action.yml or action.yaml for ${uses_value}"
            status=1
            continue
        fi

        runtime="$(read_runtime "${metadata_file}")"
        case "${runtime}" in
            node12 | node16 | node20)
                echo "::error file=${workflow_file},title=Deprecated action runtime::${uses_value} declares runs.using=${runtime}"
                status=1
                ;;
            "")
                echo "::error file=${workflow_file},title=Missing action runtime::${uses_value} metadata has no runs.using value"
                status=1
                ;;
            *)
                echo "ok ${uses_value} uses ${runtime}"
                ;;
        esac
    done < <(extract_uses "${workflow_file}")
done < <(find "${workflows_dir}" -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 | sort -z)

exit "${status}"
