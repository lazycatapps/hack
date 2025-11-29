#!/bin/bash
# init-project.sh - Project initialization script for Lazycat Apps
# Single entry point for initializing projects

set -euo pipefail

#############################################
# Configuration
#############################################

HACK_REPO_BRANCH="${HACK_REPO_BRANCH:-main}"
HACK_REPO_URL="https://raw.githubusercontent.com/lazycatapps/hack/${HACK_REPO_BRANCH}"
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
HACK_LOCAL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Git configuration
GIT_USER_NAME="${GIT_USER_NAME:-user}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-user@users.noreply.github.com}"
SYNC_INCLUDE_INIT_FILES="false"
SYNC_SELECTED_TARGET=""
SYNC_WORKFLOW_TYPE=""
INIT_APP_ID_PREFIX="${APP_ID_PREFIX:-}"

# CLI state placeholders (populated during argument parsing)
CLI_MODE="interactive"
CLI_PROJECT_NAME=""
CLI_TYPE="lpk-only"

# Project type metadata (order determines menu display and fallback defaults)
# Fields: key|display|aliases|trigger|additional|hints
PROJECT_TYPE_RECORDS=(
    "key=lpk-only|display=LPK only|aliases=lpk-only,lpk|trigger=lpk-package.yml|additional=|hints=|description=适用于仅生成 LPK 包（不包含容器镜像）"
    "key=docker-lpk|display=Docker image + LPK|aliases=docker-lpk,docker|trigger=docker-image.yml,lpk-package.yml|additional=cleanup-docker-tags.yml,reusable-docker-image.yml|hints=.github/workflows/docker-image.yml,.github/workflows/reusable-docker-image.yml,.github/workflows/includes/docker-image.reusable.yml|description=适用于同时需要 Docker 镜像与 LPK 包用于部署"
)

# Sync target metadata (order determines menu display)
# Fields: key|label|aliases
SYNC_TARGET_RECORDS=(
    "key=all|label=全部文件 (All files)|aliases=all,All files,全部文件 (All files),1"
    "key=makefile|label=仅 Makefile (Makefile only)|aliases=makefile,Makefile only,仅 Makefile (Makefile only),2"
    "key=workflows|label=仅工作流 (Workflows only)|aliases=workflows,Workflows only,仅工作流 (Workflows only),3"
    "key=configs|label=仅通用配置 (Common configs only)|aliases=configs,config,Common configs only,仅通用配置 (Common configs only),4"
)

#############################################
# Utility functions
#############################################

# Color output
print_info() { echo -e "\033[34m[INFO]\033[0m $*"; }
print_success() { echo -e "\033[32m[SUCCESS]\033[0m $*"; }
print_error() { echo -e "\033[31m[ERROR]\033[0m $*" >&2; }
print_warning() { echo -e "\033[33m[WARNING]\033[0m $*"; }

run_sed_in_place() {
    local target="$1"
    shift

    if [[ "${OSTYPE-}" == "darwin"* ]]; then
        sed -i "" "$@" "$target"
    else
        sed -i "$@" "$target"
    fi
}

missing_option_value() {
    local option="$1"
    print_error "Option $option requires a value"
    show_help
    exit 1
}

reset_cli_state() {
    CLI_MODE="interactive"
    CLI_PROJECT_NAME=""
    CLI_TYPE="lpk-only"
}

parse_cli_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type|-t)
                if [[ $# -lt 2 ]]; then
                    missing_option_value "$1"
                fi
                CLI_TYPE="$2"
                CLI_MODE="quick"
                shift 2
                ;;
            --name|-n)
                if [[ $# -lt 2 ]]; then
                    missing_option_value "$1"
                fi
                CLI_PROJECT_NAME="$2"
                CLI_MODE="quick"
                shift 2
                ;;
            --sync|-s)
                CLI_MODE="sync"
                shift
                ;;
            --sync-include-init|-I)
                SYNC_INCLUDE_INIT_FILES="true"
                shift
                ;;
            --sync-target|-T)
                if [[ $# -lt 2 ]]; then
                    missing_option_value "$1"
                fi
                SYNC_SELECTED_TARGET="$2"
                shift 2
                ;;
            --sync-workflow-type|-W)
                if [[ $# -lt 2 ]]; then
                    missing_option_value "$1"
                fi
                SYNC_WORKFLOW_TYPE="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

safe_to_lower() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

normalize_token_compact() {
    local token
    token=$(safe_to_lower "$1")
    token="${token// /}"
    token="${token//(/}"
    token="${token//)/}"
    token="${token//+/}"
    printf '%s\n' "$token"
}

get_record_field() {
    local record="$1"
    local field="$2"
    local IFS='|'
    local part
    local -a parts=()
    read -ra parts <<< "$record"
    for part in "${parts[@]}"; do
        if [[ "$part" == "$field="* ]]; then
            printf '%s\n' "${part#"$field="}"
            return 0
        fi
    done
    return 1
}

csv_to_lines() {
    local csv="${1-}"
    if [ -z "$csv" ]; then
        return 0
    fi

    local IFS=','
    local entry
    local -a entries=()
    read -ra entries <<< "$csv"
    if [ ${#entries[@]} -eq 0 ]; then
        return 0
    fi

    for entry in "${entries[@]}"; do
        local trimmed_entry
        trimmed_entry=$(trim "$entry")
        [ -n "$trimmed_entry" ] || continue
        printf '%s\n' "$trimmed_entry"
    done
}

project_type_record_by_index() {
    local index="$1"
    if [ "$index" -ge 0 ] && [ "$index" -lt "${#PROJECT_TYPE_RECORDS[@]}" ]; then
        printf '%s\n' "${PROJECT_TYPE_RECORDS[$index]}"
        return 0
    fi
    return 1
}

project_type_record_by_key() {
    local key="$1"
    local record
    for record in "${PROJECT_TYPE_RECORDS[@]}"; do
        local record_key
        record_key=$(get_record_field "$record" "key") || continue
        if [ "$record_key" = "$key" ]; then
            printf '%s\n' "$record"
            return 0
        fi
    done
    return 1
}

project_type_display_name() {
    local type="$1"
    local record
    record=$(project_type_record_by_key "$type") || return 1
    get_record_field "$record" "display"
}

project_type_trigger_files() {
    local type="$1"
    local record
    record=$(project_type_record_by_key "$type") || return 1
    local raw
    raw=$(get_record_field "$record" "trigger") || return 0
    csv_to_lines "$raw"
}

project_type_additional_workflow_files() {
    local type="$1"
    local record
    record=$(project_type_record_by_key "$type") || return 1
    local raw
    raw=$(get_record_field "$record" "additional") || return 0
    csv_to_lines "$raw"
}

normalize_project_type() {
    local raw_input="$1"
    if [ -z "$raw_input" ]; then
        return 1
    fi

    local trimmed_input
    trimmed_input=$(trim "$raw_input")
    if [ -z "$trimmed_input" ]; then
        return 1
    fi

    local lower_value
    lower_value=$(safe_to_lower "$trimmed_input")

    if [[ "$lower_value" =~ ^[0-9]+$ ]]; then
        local numeric=$((lower_value - 1))
        local record=""
        record=$(project_type_record_by_index "$numeric") || record=""
        if [ -n "$record" ]; then
            get_record_field "$record" "key"
            return 0
        fi
    fi

    local compact_value
    compact_value=$(normalize_token_compact "$trimmed_input")

    local record
    for record in "${PROJECT_TYPE_RECORDS[@]}"; do
        local key
        key=$(get_record_field "$record" "key") || continue
        local key_lower
        key_lower=$(safe_to_lower "$key")
        local key_compact
        key_compact=$(normalize_token_compact "$key")
        if [ "$lower_value" = "$key_lower" ] || [ "$compact_value" = "$key_compact" ]; then
            printf '%s\n' "$key"
            return 0
        fi

        local display
        display=$(get_record_field "$record" "display")
        local display_lower
        display_lower=$(safe_to_lower "$display")
        local display_compact
        display_compact=$(normalize_token_compact "$display")
        if [ "$lower_value" = "$display_lower" ] || [ "$compact_value" = "$display_compact" ]; then
            printf '%s\n' "$key"
            return 0
        fi

        local alias_list
        alias_list=$(get_record_field "$record" "aliases")
        if [ -n "$alias_list" ]; then
            local alias
            local -a alias_array=()
            IFS=',' read -ra alias_array <<< "$alias_list"
            for alias in "${alias_array[@]}"; do
                local trimmed_alias
                trimmed_alias=$(trim "$alias")
                [ -n "$trimmed_alias" ] || continue
                local alias_lower
                alias_lower=$(safe_to_lower "$trimmed_alias")
                local alias_compact
                alias_compact=$(normalize_token_compact "$trimmed_alias")
                if [ "$lower_value" = "$alias_lower" ] || [ "$compact_value" = "$alias_compact" ]; then
                    printf '%s\n' "$key"
                    return 0
                fi
            done
        fi
    done

    return 1
}

prompt_for_project_type() {
    local prompt="$1"
    local -a options=()
    local record
    for record in "${PROJECT_TYPE_RECORDS[@]}"; do
        local display
        display=$(get_record_field "$record" "display")
        local description
        if ! description=$(get_record_field "$record" "description"); then
            description=""
        fi
        if [ -n "$description" ]; then
            options+=("$display - $description")
        else
            options+=("$display")
        fi
    done
    local choice
    choice=$(select_option "$prompt" "${options[@]}")
    local index=$((choice - 1))
    local selected_record
    selected_record=$(project_type_record_by_index "$index") || return 1
    get_record_field "$selected_record" "key"
}

detect_project_type() {
    local record
    for record in "${PROJECT_TYPE_RECORDS[@]}"; do
        local key
        key=$(get_record_field "$record" "key") || continue
        local hints
        hints=$(get_record_field "$record" "hints")
        if [ -z "$hints" ]; then
            continue
        fi
        local hint
        local -a hint_array=()
        IFS=',' read -ra hint_array <<< "$hints"
        for hint in "${hint_array[@]}"; do
            local trimmed_hint
            trimmed_hint=$(trim "$hint")
            [ -n "$trimmed_hint" ] || continue
            if [ -f "$trimmed_hint" ]; then
                printf '%s\n' "$key"
                return 0
            fi
        done
    done
    local first_record="${PROJECT_TYPE_RECORDS[0]}"
    get_record_field "$first_record" "key"
}

sync_target_record_by_index() {
    local index="$1"
    if [ "$index" -ge 0 ] && [ "$index" -lt "${#SYNC_TARGET_RECORDS[@]}" ]; then
        printf '%s\n' "${SYNC_TARGET_RECORDS[$index]}"
        return 0
    fi
    return 1
}

sync_target_record_by_key() {
    local key="$1"
    local record
    for record in "${SYNC_TARGET_RECORDS[@]}"; do
        local record_key
        record_key=$(get_record_field "$record" "key") || continue
        if [ "$record_key" = "$key" ]; then
            printf '%s\n' "$record"
            return 0
        fi
    done
    return 1
}

normalize_sync_target() {
    local raw_input="$1"
    if [ -z "$raw_input" ]; then
        return 1
    fi

    local trimmed_input
    trimmed_input=$(trim "$raw_input")
    if [ -z "$trimmed_input" ]; then
        return 1
    fi

    local lower_value
    lower_value=$(safe_to_lower "$trimmed_input")

    if [[ "$lower_value" =~ ^[0-9]+$ ]]; then
        local numeric=$((lower_value - 1))
        local record=""
        record=$(sync_target_record_by_index "$numeric") || record=""
        if [ -n "$record" ]; then
            get_record_field "$record" "key"
            return 0
        fi
    fi

    local compact_value
    compact_value=$(normalize_token_compact "$trimmed_input")

    local record
    for record in "${SYNC_TARGET_RECORDS[@]}"; do
        local key
        key=$(get_record_field "$record" "key") || continue
        local key_lower
        key_lower=$(safe_to_lower "$key")
        local key_compact
        key_compact=$(normalize_token_compact "$key")
        if [ "$lower_value" = "$key_lower" ] || [ "$compact_value" = "$key_compact" ]; then
            printf '%s\n' "$key"
            return 0
        fi

        local label
        label=$(get_record_field "$record" "label")
        local label_lower
        label_lower=$(safe_to_lower "$label")
        local label_compact
        label_compact=$(normalize_token_compact "$label")
        if [ "$lower_value" = "$label_lower" ] || [ "$compact_value" = "$label_compact" ]; then
            printf '%s\n' "$key"
            return 0
        fi

        local alias_list
        alias_list=$(get_record_field "$record" "aliases")
        if [ -n "$alias_list" ]; then
            local alias
            local -a alias_array=()
            IFS=',' read -ra alias_array <<< "$alias_list"
            for alias in "${alias_array[@]}"; do
                local trimmed_alias
                trimmed_alias=$(trim "$alias")
                [ -n "$trimmed_alias" ] || continue
                local alias_lower
                alias_lower=$(safe_to_lower "$trimmed_alias")
                local alias_compact
                alias_compact=$(normalize_token_compact "$trimmed_alias")
                if [ "$lower_value" = "$alias_lower" ] || [ "$compact_value" = "$alias_compact" ]; then
                    printf '%s\n' "$key"
                    return 0
                fi
            done
        fi
    done

    return 1
}

prompt_for_sync_target() {
    local prompt="$1"
    local -a options=()
    local record
    for record in "${SYNC_TARGET_RECORDS[@]}"; do
        options+=("$(get_record_field "$record" "label")")
    done
    local choice
    choice=$(select_option "$prompt" "${options[@]}")
    local index=$((choice - 1))
    local selected_record
    selected_record=$(sync_target_record_by_index "$index") || return 1
    get_record_field "$selected_record" "key"
}

sync_target_label() {
    local key="$1"
    local record
    record=$(sync_target_record_by_key "$key") || return 1
    get_record_field "$record" "label"
}

detect_repo_mode() {
    local override="${HACK_REPO_MODE:-}"
    if [ -n "$override" ]; then
        case "$override" in
            local|remote)
                echo "$override"
                return
                ;;
            *)
                print_warning "Unknown HACK_REPO_MODE override: $override, falling back to auto detection"
                ;;
        esac
    fi

    if [ -d "$HACK_LOCAL_ROOT/.git" ] && [ -f "$HACK_LOCAL_ROOT/scripts/lazycli.sh" ]; then
        echo "local"
        return
    fi

    echo "remote"
}

download_remote_file() {
    local url="$1"
    local target="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$target"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$target" "$url"
    else
        print_error "Neither curl nor wget is available"
        exit 1
    fi
}

HACK_REPO_MODE="$(detect_repo_mode)"
if [ "$HACK_REPO_MODE" = "local" ]; then
    print_info "Repository mode: local (source: $HACK_LOCAL_ROOT)"
else
    print_info "Repository mode: remote (source: $HACK_REPO_URL)"
fi

fetch_file() {
    local relative_path="$1"
    local target="$2"

    if [ "$HACK_REPO_MODE" = "local" ]; then
        local source_path="$HACK_LOCAL_ROOT/$relative_path"
        if [ ! -f "$source_path" ]; then
            print_error "Local file not found: $source_path"
            exit 1
        fi
        cp "$source_path" "$target"
    else
        download_remote_file "$HACK_REPO_URL/$relative_path" "$target"
    fi
}

MODE_INIT="init"
MODE_SYNC="sync"

is_truthy() {
    case "$1" in
        1|true|TRUE|yes|YES|on|ON)
            return 0
            ;;
    esac
    return 1
}

copy_policy_resolve() {
    local mode="$1"
    local include_init="$2"

    COPY_POLICY_FORCE="false"
    COPY_POLICY_PRESERVE_HINT="true"
    COPY_POLICY_OVERWRITE_NOTICE="false"

    if [ "$mode" = "$MODE_INIT" ]; then
        COPY_POLICY_FORCE="true"
        COPY_POLICY_PRESERVE_HINT="false"
        return 0
    fi

    if [ "$mode" = "$MODE_SYNC" ]; then
        if is_truthy "$include_init"; then
            COPY_POLICY_FORCE="true"
            COPY_POLICY_PRESERVE_HINT="false"
            COPY_POLICY_OVERWRITE_NOTICE="true"
        else
            COPY_POLICY_FORCE="false"
            COPY_POLICY_PRESERVE_HINT="true"
        fi
        return 0
    fi

    return 0
}

sync_asset() {
    local relative_path="$1"
    local target="$2"
    local mode="${3:-$MODE_INIT}"
    local include_init="${4:-false}"
    local label_param="${5-}"
    local copied_var="${6-}"
    local label

    if [ -n "$label_param" ]; then
        label="$label_param"
    else
        label="$target"
    fi

    copy_policy_resolve "$mode" "$include_init"
    local force_copy="$COPY_POLICY_FORCE"
    local preserve_hint="$COPY_POLICY_PRESERVE_HINT"
    local overwrite_notice="$COPY_POLICY_OVERWRITE_NOTICE"

    local force_override="${SYNC_ASSET_FORCE_OVERRIDE:-}"
    local preserve_override="${SYNC_ASSET_PRESERVE_HINT_OVERRIDE:-}"
    local overwrite_override="${SYNC_ASSET_OVERWRITE_NOTICE_OVERRIDE:-}"

    if [ "${SYNC_ASSET_FORCE_OVERRIDE+x}" != "" ]; then
        if is_truthy "$force_override"; then
            force_copy="true"
        else
            force_copy="false"
        fi
    fi

    if [ "${SYNC_ASSET_PRESERVE_HINT_OVERRIDE+x}" != "" ]; then
        if is_truthy "$preserve_override"; then
            preserve_hint="true"
        else
            preserve_hint="false"
        fi
    fi

    if [ "${SYNC_ASSET_OVERWRITE_NOTICE_OVERRIDE+x}" != "" ]; then
        if is_truthy "$overwrite_override"; then
            overwrite_notice="true"
        else
            overwrite_notice="false"
        fi
    fi

    local should_copy="false"
    if is_truthy "$force_copy" || [ ! -f "$target" ]; then
        should_copy="true"
    fi

    local asset_copied="false"

    if [ "$should_copy" != "true" ]; then
        if is_truthy "$preserve_hint"; then
            print_info "$label preserved (sync mode without --sync-include-init)"
        else
            print_info "$label preserved"
        fi
    else
        local target_dir
        target_dir=$(dirname "$target")
        if [ "$target_dir" != "." ] && [ -n "$target_dir" ]; then
            mkdir -p "$target_dir"
        fi

        if is_truthy "$force_copy" && [ "$mode" = "$MODE_SYNC" ] && is_truthy "$overwrite_notice" && [ -f "$target" ]; then
            print_warning "Overwriting $label to mirror init assets (--sync-include-init)"
        elif [ ! -f "$target" ]; then
            print_warning "$label missing locally; restoring from template"
        else
            print_info "Updating $label from template"
        fi

        local tmp_file
        tmp_file=$(mktemp)
        fetch_file "$relative_path" "$tmp_file"
        if ! mv "$tmp_file" "$target"; then
            rm -f "$tmp_file"
            print_error "Failed to place $label at $target"
            exit 1
        fi
        asset_copied="true"
        print_success "$label copied"
    fi

    if [ -n "$copied_var" ]; then
        printf -v "$copied_var" '%s' "$asset_copied"
    fi

    unset SYNC_ASSET_FORCE_OVERRIDE
    unset SYNC_ASSET_PRESERVE_HINT_OVERRIDE
    unset SYNC_ASSET_OVERWRITE_NOTICE_OVERRIDE
}

sync_asset_force() {
    local relative_path="$1"
    local target="$2"
    local mode="${3:-$MODE_SYNC}"
    local include_init="${4:-true}"
    local label="${5-}"
    local copied_var="${6-}"

    SYNC_ASSET_FORCE_OVERRIDE=true \
    SYNC_ASSET_PRESERVE_HINT_OVERRIDE=false \
    SYNC_ASSET_OVERWRITE_NOTICE_OVERRIDE=false \
        sync_asset "$relative_path" "$target" "$mode" "$include_init" "$label" "$copied_var"
}

# Interactive selection menu (returns 1-based index)
select_option() {
    local prompt="$1"
    shift
    local options=("$@")

    if [ ! -t 0 ]; then
        print_error "无法在非交互模式中完成选择: $prompt"
        exit 1
    fi

    printf "%s\n" "$prompt" >&2
    for i in "${!options[@]}"; do
        printf "  [%d] %s\n" "$((i+1))" "${options[$i]}" >&2
    done

    while true; do
        printf "请选择 [1-%d]: " "${#options[@]}" >&2
        IFS= read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
            echo "$choice"
            return 0
        fi
        print_error "无效选择,请重新输入"
    done
}

# Copy workflows
copy_workflows() {
    local type="$1"
    local mode="${2:-$MODE_INIT}"
    local include_init="${3:-false}"
    local target_dir=".github/workflows"

    if [ "$mode" = "$MODE_INIT" ]; then
        include_init="true"
    fi

    print_info "Copying workflow files..."
    mkdir -p "$target_dir"

    # Always include shared workflows
    sync_asset_force "workflows/common/cleanup-artifacts.yml" "$target_dir/cleanup-artifacts.yml" "$mode" "$include_init"
    sync_asset_force "workflows/common/reusable-lpk-package.yml" "$target_dir/reusable-lpk-package.yml" "$mode" "$include_init"

    if ! project_type_record_by_key "$type" >/dev/null 2>&1; then
        print_warning "Unknown workflow type: $type, skipping type-specific workflows"
        print_success "Workflows copied"
        return 0
    fi

    local base_path="workflows/$type"

    local additional_files
    additional_files=$(project_type_additional_workflow_files "$type")
    if [ -n "$additional_files" ]; then
        while IFS= read -r extra; do
            [ -n "$extra" ] || continue
            sync_asset_force "$base_path/$extra" "$target_dir/$extra" "$mode" "$include_init"
        done <<EOF
$additional_files
EOF
    fi

    local trigger_files
    trigger_files=$(project_type_trigger_files "$type")

    if [ "$mode" = "$MODE_SYNC" ] && is_truthy "$include_init"; then
        print_warning "Overwriting trigger workflows during sync because --sync-include-init is enabled"
    fi

    if [ -n "$trigger_files" ]; then
        while IFS= read -r trigger; do
            [ -n "$trigger" ] || continue
            local target_path="$target_dir/$trigger"
            sync_asset "$base_path/$trigger" "$target_path" "$mode" "$include_init"
        done <<EOF
$trigger_files
EOF
    fi

    print_success "Workflows copied"
}

# Copy Makefile template
copy_makefile() {
    local mode="${1:-$MODE_INIT}"
    local include_init="${2:-false}"
    local project_type="${3:-}"

    local copied="false"
    sync_asset "Makefile" "Makefile" "$mode" "$include_init" "Makefile" copied

    if [ "$copied" = "true" ] && [ -n "$project_type" ]; then
        local tmp_file
        tmp_file=$(mktemp)
        if sed "s/^PROJECT_TYPE[[:space:]]\?=.*$/PROJECT_TYPE ?= ${project_type}  # (lpk-only | docker-lpk)/" Makefile >"$tmp_file"; then
            if ! mv "$tmp_file" Makefile; then
                rm -f "$tmp_file"
                print_error "Failed to update PROJECT_TYPE in Makefile"
                exit 1
            fi
        else
            rm -f "$tmp_file"
            print_error "Failed to update PROJECT_TYPE in Makefile"
            exit 1
        fi
        print_info "Updated Makefile PROJECT_TYPE to ${project_type}"
    fi

    print_info "Checking APP_ID_PREFIX configuration... copied=$copied, mode=$mode, include_init=$include_init, INIT_APP_ID_PREFIX=$INIT_APP_ID_PREFIX"
    if [ "$copied" = "true" ] && [ -n "$INIT_APP_ID_PREFIX" ]; then
        if [ "$mode" = "$MODE_INIT" ] || [ "$include_init" = "true" ]; then
            if ! run_sed_in_place "Makefile" "-e" "s/^[[:space:]]*APP_ID_PREFIX[[:space:]]*[?:]*=.*/APP_ID_PREFIX ?= ${INIT_APP_ID_PREFIX}/"; then
                print_error "Failed to persist APP_ID_PREFIX in Makefile"
                exit 1
            fi
            print_info "Persisted APP_ID_PREFIX to Makefile"
        fi
    fi
}

# Sync common assets (base configs + icon)
sync_common_assets() {
    local mode="${1:-$MODE_INIT}"
    local include_init="${2:-false}"
    local include_base="${3:-true}"

    if [ "$mode" = "$MODE_INIT" ]; then
        include_init="true"
    fi

    print_info "Syncing common assets..."

    if [ "$include_base" != "false" ]; then
        sync_asset_force "base.mk" "base.mk" "$mode" "$include_init"
    fi

    sync_asset ".gitignore" ".gitignore" "$mode" "$include_init"
    sync_asset ".editorconfig" ".editorconfig" "$mode" "$include_init"
    sync_asset "lzc-build.yml" "lzc-build.yml" "$mode" "$include_init"
    sync_asset "icon.png" "icon.png" "$mode" "$include_init" "icon.png"

    print_success "Common assets synchronized"
}

cleanup_unused_files() {
    print_info "Cleaning deprecated files..."

    local removed="false"
    local stale_paths=(
        ".github/workflows/lazycat-login.exp"
    )
    local stale_dirs=()

    for stale_path in "${stale_paths[@]}"; do
        if [ -e "$stale_path" ]; then
            rm -f "$stale_path"
            print_info "Removed: $stale_path"
            removed="true"
        fi
    done

    if [ "${#stale_dirs[@]}" -gt 0 ]; then
        for stale_dir in "${stale_dirs[@]}"; do
            if [ -d "$stale_dir" ]; then
                rm -rf "$stale_dir"
                print_info "Removed directory: $stale_dir"
                removed="true"
            fi
        done
    fi

    if [ "$removed" = "true" ]; then
        print_success "Deprecated files removed"
    else
        print_info "No deprecated files detected"
    fi
}

# Initialize Git
init_git() {
    if [ ! -d ".git" ]; then
        print_info "Initializing Git repository..."
        git init .

        # Configure git user info
        git config --local user.name "$GIT_USER_NAME"
        git config --local user.email "$GIT_USER_EMAIL"

        # Create initial commit
        git commit --allow-empty -m "Initial commit"

        print_success "Git repository initialized"
        print_info "Git user: $GIT_USER_NAME <$GIT_USER_EMAIL>"
    else
        print_warning "Git repository already exists"
    fi
}

# Generate README
generate_readme() {
    local project_name="$1"
    local project_type="$2"

    if [ -f "README.md" ]; then
        print_warning "README.md already exists, skipping..."
        return
    fi

    print_info "Generating README.md..."

    cat > README.md <<EOF
# $project_name

Starter project generated by Lazycat hack tooling.

## Getting Started

### Prerequisites

- Make
- Git
- lzc-cli (install with \`npm install -g @lazycatcloud/lzc-cli\`)

### Common Commands

\`\`\`bash
make help
make info
make clean
make lpk
make deploy
make uninstall
\`\`\`

EOF

    if [ "$project_type" = "docker-lpk" ]; then
        cat >> README.md <<'EOF'

### Docker Commands

```bash
make docker-build
make docker-push
make docker-run
```

EOF
    fi

    cat >> README.md <<'EOF'

## Next Steps

1. Review `Makefile` and set project metadata.
2. Run `make help` to explore available targets.

EOF

    print_success "README.md generated"
}

#############################################
# Main functionality
#############################################

# Interactive initialization
interactive_init() {
    echo ""
    print_info "Welcome to Lazycat Apps Project Initialization Tool"
    echo ""

    # 1. Select build type
    local type_code
    type_code=$(prompt_for_project_type "Select build type:")
    local build_type
    build_type=$(project_type_display_name "$type_code") || build_type="$type_code"

    # 2. Enter project name
    local project_name
    read -rp "Enter project name: " project_name

    if [ -z "$project_name" ]; then
        print_error "Project name cannot be empty"
        exit 1
    fi

    # 3. Confirm
    echo ""
    print_info "Configuration:"
    echo "  Build type: $build_type"
    echo "  Project name: $project_name"
    echo ""

    read -rp "Confirm initialization? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_warning "Cancelled"
        exit 0
    fi

    # 4. Execute initialization
    do_init "$project_name" "$type_code"
}

# Quick initialization
quick_init() {
    local project_name="$1"
    local type="$2"

    echo ""
    print_info "Quick initialization"
    echo "  Project name: $project_name"
    local type_display
    type_display=$(project_type_display_name "$type") || type_display="$type"
    echo "  Project type: $type_display"
    echo "  App ID prefix: $INIT_APP_ID_PREFIX"
    echo ""
    do_init "$project_name" "$type"
}

# Core initialization logic
do_init() {
    local project_name="$1"
    local type="$2"

    # Create project directory if needed
    if [ -n "$project_name" ]; then
        if [ -d "$project_name" ]; then
            print_error "Directory $project_name already exists"
            exit 1
        fi
        mkdir -p "$project_name"
        cd "$project_name" || exit 1
        print_info "Created and entered directory: $project_name"
    fi

    # Copy files
    sync_common_assets "$MODE_INIT" "true"
    copy_makefile "$MODE_INIT" "true" "$type"
    copy_workflows "$type" "$MODE_INIT"
    generate_readme "$project_name" "$type"

    # Initialize Git
    echo ""
    read -rp "Initialize Git repository? [Y/n]: " init_git_confirm
    if [[ ! "$init_git_confirm" =~ ^[Nn]$ ]]; then
        init_git
    fi

    echo ""
    print_success "Project initialization completed!"
    echo ""
    print_info "Next steps:"
    if [ -n "$project_name" ]; then
        echo "  1. cd $project_name"
        echo "  2. Start development"
        echo "  3. make help  # View available commands"
    else
        echo "  1. Start development"
        echo "  2. make help  # View available commands"
    fi
}

# Sync files to existing project
sync_files() {
    local include_init="${1:-false}"
    local preset_target_raw="${2:-}"
    local preset_workflow_type_raw="${3:-}"
    print_info "Syncing files to current project..."

    if [ "$include_init" = "true" ]; then
        print_warning "Sync will overwrite init-only workflow triggers (e.g. docker-image.yml)"
    fi
    echo ""

    # Ask what to sync
    local preset_target=""
    if [ -n "$preset_target_raw" ]; then
        if preset_target=$(normalize_sync_target "$preset_target_raw"); then
            :
        else
            print_error "未知同步类型: $preset_target_raw"
            exit 1
        fi
    fi

    local preset_workflow_type=""
    if [ -n "$preset_workflow_type_raw" ]; then
        if preset_workflow_type=$(normalize_project_type "$preset_workflow_type_raw"); then
            :
        else
            print_error "未知工作流类型: $preset_workflow_type_raw"
            exit 1
        fi
    fi

    local sync_target="$preset_target"
    if [ "$include_init" = "true" ] && [ -z "$sync_target" ]; then
        sync_target="all"
        local all_label
        all_label=$(sync_target_label "all") || all_label="All files"
        print_info "--sync-include-init detected, defaulting to $all_label to mirror init assets"
    fi

    if [ -z "$sync_target" ]; then
        if [ ! -t 0 ]; then
            sync_target="all"
            local default_label
            default_label=$(sync_target_label "all") || default_label="All files"
            print_warning "非交互环境检测到, 同步内容默认选择 $default_label"
        else
            local summary_parts=()
            local idx=0
            local record
            for record in "${SYNC_TARGET_RECORDS[@]}"; do
                local label
                label=$(get_record_field "$record" "label")
                summary_parts+=("$((idx + 1))=$label")
                idx=$((idx + 1))
            done
            print_info "同步选项: ${summary_parts[*]}"
            sync_target=$(prompt_for_sync_target "请选择同步的内容:")
        fi
    fi

    if [ "$include_init" = "true" ] && [ "$sync_target" != "all" ]; then
        local override_label
        override_label=$(sync_target_label "all") || override_label="All files"
        print_warning "--sync-include-init requires full init asset sync; overriding target to $override_label"
        sync_target="all"
    fi

    case "$sync_target" in
        "all")
            sync_common_assets "$MODE_SYNC" "$include_init"
            local detected_type
            detected_type=$(detect_project_type)
            copy_makefile "$MODE_SYNC" "$include_init" "$detected_type"
            copy_workflows "$detected_type" "$MODE_SYNC" "$include_init"
            ;;
        "makefile")
            sync_asset_force "base.mk" "base.mk" "$MODE_SYNC" "true"
            local makefile_type="$preset_workflow_type"
            if [ -z "$makefile_type" ]; then
                makefile_type=$(detect_project_type)
            fi
            copy_makefile "$MODE_SYNC" "true" "$makefile_type"
            ;;
        "workflows")
            local type="$preset_workflow_type"
            if [ -z "$type" ]; then
                if [ ! -t 0 ]; then
                    print_error "非交互同步需通过 --sync-workflow-type 指定工作流类型"
                    exit 1
                fi
                local type_summary=()
                local idx=0
                local record
                for record in "${PROJECT_TYPE_RECORDS[@]}"; do
                    local label
                    label=$(get_record_field "$record" "display")
                    type_summary+=("$((idx + 1))=$label")
                    idx=$((idx + 1))
                done
                print_info "工作流选项: ${type_summary[*]}"
                type=$(prompt_for_project_type "请选择工作流类型:")
            fi
            copy_workflows "$type" "$MODE_SYNC" "$include_init"
            ;;
        "configs")
            sync_common_assets "$MODE_SYNC" "$include_init" "false"
            ;;
        *)
            print_error "未知同步类型: $sync_target"
            exit 1
            ;;
    esac

    cleanup_unused_files

    echo ""
    print_success "Sync completed!"
}

# Show help
show_help() {
    cat <<EOF
Lazycat Apps Project Initialization Tool

Usage:
  Interactive mode:
    $0

  Quick initialization:
    $0 --type TYPE --name NAME

  Sync files to existing project:
    $0 --sync

  Remote execution:
    bash <(curl -fsSL https://raw.githubusercontent.com/lazycatapps/hack/main/scripts/lazycli.sh)

Parameters:
  --type TYPE, -t TYPE
                   Project type (lpk-only | docker-lpk) [default: lpk-only]
  --name NAME, -n NAME
                   Project name (required for quick mode)
  --sync, -s       Sync mode, update existing project
  --sync-include-init, -I
                   Sync mode: also overwrite init-only files (e.g. docker-image.yml)
  --sync-target TARGET, -T TARGET
                   Sync mode: selection (all | makefile | workflows | configs)
  --sync-workflow-type TYPE, -W TYPE
                   Sync mode + workflows: workflow set (lpk-only | docker-lpk)
  --help, -h       Show this help

Environment Variables:
  HACK_REPO_BRANCH    Branch to use (default: main)
  HACK_REPO_MODE      Force mode detection (local | remote, default: auto)
  GIT_USER_NAME       Git user name (default: user)
  GIT_USER_EMAIL      Git user email (default: user@users.noreply.github.com)
  APP_ID_PREFIX       Application ID prefix persisted to Makefile during init

Examples:
  # Interactive mode
  $0

  # Quick init with default type (lpk-only)
  $0 --name my-library

  # Quick init LPK project (explicit)
  $0 --type lpk-only --name my-library

  # Quick init using short flags
  $0 -t docker-lpk -n my-service

  # Quick init Docker + LPK project
  $0 --type docker-lpk --name my-service

  # Sync files
  cd my-project && $0 --sync

  # Sync workflows including init-only triggers
  cd my-project && $0 --sync --sync-include-init

  # Sync with short flags
  cd my-project && $0 -s -T workflows -W docker-lpk
  # Non-interactive sync choosing specific target
  bash <(curl -fsSL https://raw.githubusercontent.com/lazycatapps/hack/main/scripts/lazycli.sh) --sync --sync-target workflows --sync-workflow-type docker-lpk

  # Use different branch
  HACK_REPO_BRANCH=develop $0 --name=test-project

  # Custom git user
  GIT_USER_NAME="John Doe" GIT_USER_EMAIL="john@example.com" $0 --name=my-project

  # Remote execution (keeps interactive prompts)
  bash <(curl -fsSL https://raw.githubusercontent.com/lazycatapps/hack/main/scripts/lazycli.sh)

  # Remote execution with custom git user
  GIT_USER_NAME="John Doe" GIT_USER_EMAIL="john@example.com" \
    bash <(curl -fsSL https://raw.githubusercontent.com/lazycatapps/hack/main/scripts/lazycli.sh)
EOF
}

#############################################
# Main entry point
#############################################

main() {
    reset_cli_state
    parse_cli_arguments "$@"

    local mode="$CLI_MODE"
    local project_name="$CLI_PROJECT_NAME"
    local type="$CLI_TYPE"

    if [ "$SYNC_INCLUDE_INIT_FILES" = "true" ] && [ "$mode" != "$MODE_SYNC" ]; then
        print_error "--sync-include-init must be used together with --sync"
        exit 1
    fi

    local normalized_type
    if normalized_type=$(normalize_project_type "$type"); then
        type="$normalized_type"
    else
        print_error "Invalid --type value: $type (expected lpk-only|docker-lpk)"
        exit 1
    fi

    if [ -n "$SYNC_SELECTED_TARGET" ]; then
        local normalized_target
        if normalized_target=$(normalize_sync_target "$SYNC_SELECTED_TARGET"); then
            SYNC_SELECTED_TARGET="$normalized_target"
        else
            print_error "Invalid --sync-target value: $SYNC_SELECTED_TARGET (expected all|makefile|workflows|configs)"
            exit 1
        fi
    fi

    if [ -n "$SYNC_WORKFLOW_TYPE" ]; then
        local normalized_workflow_type
        if normalized_workflow_type=$(normalize_project_type "$SYNC_WORKFLOW_TYPE"); then
            SYNC_WORKFLOW_TYPE="$normalized_workflow_type"
        else
            print_error "Invalid --sync-workflow-type value: $SYNC_WORKFLOW_TYPE (expected lpk-only|docker-lpk)"
            exit 1
        fi
    fi

    if [ -n "$SYNC_WORKFLOW_TYPE" ] && [ "$SYNC_SELECTED_TARGET" != "workflows" ]; then
        print_warning "--sync-workflow-type ignored because --sync-target is not workflows"
    fi

    # Execute corresponding mode
    case "$mode" in
        interactive)
            interactive_init
            ;;
        quick)
            if [ -z "$project_name" ]; then
                print_error "Quick mode requires --name argument"
                show_help
                exit 1
            fi
            quick_init "$project_name" "$type"
            ;;
        sync)
            sync_files "$SYNC_INCLUDE_INIT_FILES" "$SYNC_SELECTED_TARGET" "$SYNC_WORKFLOW_TYPE"
            ;;
    esac
}

# Run
main "$@"
