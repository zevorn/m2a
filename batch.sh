#!/bin/bash
set -euo pipefail

MAX_SIZE=$((8 * 1024 * 1024))

print_usage() {
    cat <<'USAGE'
Usage:
  batch.sh -o <output_root> -s <start_yyyymmdd> -e <end_yyyymmdd> -r <repo_url|name=url> [-r ...] [-w <repos_dir>]

Example:
  ./batch.sh -o ./out -s 20260110 -e 20260116 \
    -r linux-mm=https://lore.kernel.org/linux-mm/2 \
    -r linux-kvm=https://lore.kernel.org/kvm/1 \
    -r linux-riscv=https://lore.kernel.org/linux-riscv/0 \
    -r rust-for-linux=https://lore.kernel.org/rust-for-linux/0 \
    -r qemu-devel=https://lore.kernel.org/qemu-devel/3

Notes:
  - Repositories are reset to historical commits (destructive).
  - Per-repo outputs are overwritten under <output_root>.
  - Merged output is written to <output_root>/merged as merged_N.txt files.
USAGE
}

error_exit() {
    echo "Error: $1" >&2
    exit 1
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || error_exit "Missing command: $1"
}

validate_ymd() {
    local ymd="$1"
    if ! [[ "$ymd" =~ ^[0-9]{8}$ ]]; then
        error_exit "Invalid date format: $ymd (expected YYYYMMDD)"
    fi

    local month=$((10#${ymd:4:2}))
    local day=$((10#${ymd:6:2}))

    if [ "$month" -lt 1 ] || [ "$month" -gt 12 ]; then
        error_exit "Invalid month in date: $ymd"
    fi
    if [ "$day" -lt 1 ] || [ "$day" -gt 31 ]; then
        error_exit "Invalid day in date: $ymd"
    fi
}

ymd_to_git_date() {
    local ymd="$1"
    echo "${ymd:0:4}-${ymd:4:2}-${ymd:6:2}"
}

sanitize_name() {
    local cleaned
    cleaned=$(echo "$1" | tr -c 'A-Za-z0-9._-' '_')
    while [[ "$cleaned" == _* ]]; do
        cleaned="${cleaned#_}"
    done
    while [[ "$cleaned" == *_ ]]; do
        cleaned="${cleaned%_}"
    done
    printf '%s' "$cleaned"
}

trim_value() {
    local value="$1"
    value="${value//$'\r'/}"
    value="${value//$'\n'/}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

normalize_url() {
    local url
    url="$(trim_value "$1")"
    url="${url%/}"
    printf '%s' "$url"
}

derive_name_from_url() {
    local url="$1"
    local clean="${url%%\?*}"
    clean="${clean%%#*}"
    clean="${clean%/}"

    local name=""
    if [[ "$clean" == *"/git/"* ]]; then
        local before_git="${clean%/git/*}"
        local list_name="${before_git##*/}"
        local tail="${clean##*/}"
        if [ -n "$list_name" ] && [ -n "$tail" ]; then
            name="${list_name}-${tail}"
        fi
    fi

    if [ -z "$name" ]; then
        name="${clean##*/}"
    fi

    if [ -z "$name" ]; then
        name="$clean"
    fi

    echo "$name"
}

add_repo_spec() {
    local spec="$1"
    local name=""
    local url=""

    spec="$(trim_value "$spec")"
    if [[ "$spec" == *"="* ]]; then
        name="$(trim_value "${spec%%=*}")"
        url="$(trim_value "${spec#*=}")"
    else
        url="$(trim_value "$spec")"
        name="$(derive_name_from_url "$url")"
    fi

    name="$(sanitize_name "$(trim_value "$name")")"
    if [ -z "$name" ] || [ -z "$url" ]; then
        error_exit "Invalid repo spec: $spec"
    fi

    if [ -n "${REPO_NAME_SEEN[$name]:-}" ]; then
        error_exit "Duplicate repo name: $name"
    fi

    REPO_NAME_SEEN["$name"]=1
    REPO_NAMES+=("$name")
    REPO_URLS+=("$url")
}

update_repo() {
    local repo_dir="$1"
    local expected_url="$2"
    local current_url=""

    current_url=$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)
    current_url="$(normalize_url "$current_url")"
    expected_url="$(normalize_url "$expected_url")"

    if [ -z "$current_url" ] || [ "$current_url" != "$expected_url" ]; then
        return 1
    fi

    git -C "$repo_dir" fetch origin
    git -C "$repo_dir" pull origin
}

safe_remove_repo() {
    local target="$1"

    if [ -z "$target" ] || [ "$target" = "/" ]; then
        error_exit "Unsafe path to remove: $target"
    fi

    case "$target" in
        "$WORK_ROOT"/*) rm -rf "$target" ;;
        *) error_exit "Refuse to remove path outside work root: $target" ;;
    esac
}

checkout_end_commit() {
    local repo_dir="$1"
    local end_ymd="$2"
    local end_git_date
    end_git_date="$(ymd_to_git_date "$end_ymd") 23:59:59"

    local commit=""
    commit=$(git -C "$repo_dir" rev-list -n 1 --before="$end_git_date" HEAD)
    if [ -z "$commit" ]; then
        error_exit "No commit found before end date $end_ymd in $repo_dir"
    fi

    git -C "$repo_dir" reset --hard "$commit"
}

merge_outputs() {
    local source_root="$1"
    local merge_dir="$2"
    local max_size="$3"
    local found=0
    local current_index=1
    local current_file=""
    local current_size=0

    mkdir -p "$merge_dir"
    rm -f "$merge_dir"/merged_*.txt

    while IFS= read -r file; do
        if [ "$found" -eq 0 ]; then
            current_file="$merge_dir/merged_${current_index}.txt"
            : > "$current_file"
            found=1
        fi

        local size
        size=$(stat -c "%s" "$file")

        if [ "$current_size" -gt 0 ] && [ $((current_size + size)) -gt "$max_size" ]; then
            current_index=$((current_index + 1))
            current_file="$merge_dir/merged_${current_index}.txt"
            : > "$current_file"
            current_size=0
        fi

        cat "$file" >> "$current_file"
        current_size=$((current_size + size))
    done < <(find "$source_root" -type f -name "[0-9][0-9][0-9][0-9][0-9][0-9]_*.txt" ! -path "$merge_dir/*" | LC_ALL=C sort)

    if [ "$found" -eq 0 ]; then
        echo "Warning: no txt files found to merge." >&2
        return
    fi

    echo "Merged files saved to: $merge_dir"
}

OUTPUT_ROOT=""
WORK_ROOT="./repos"
START_YMD=""
END_YMD=""
REPO_SPECS=()
REPO_NAMES=()
REPO_URLS=()
declare -A REPO_NAME_SEEN

while getopts ":o:w:s:e:r:h" opt; do
    case "$opt" in
        o) OUTPUT_ROOT="$OPTARG" ;;
        w) WORK_ROOT="$OPTARG" ;;
        s) START_YMD="$OPTARG" ;;
        e) END_YMD="$OPTARG" ;;
        r) REPO_SPECS+=("$OPTARG") ;;
        h) print_usage; exit 0 ;;
        \?) error_exit "Invalid option: -$OPTARG" ;;
        :) error_exit "Option -$OPTARG requires an argument" ;;
    esac
done

if [ -z "$OUTPUT_ROOT" ] || [ -z "$START_YMD" ] || [ -z "$END_YMD" ] || [ "${#REPO_SPECS[@]}" -eq 0 ]; then
    print_usage
    exit 1
fi

require_cmd git
require_cmd python

validate_ymd "$START_YMD"
validate_ymd "$END_YMD"

if [ $((10#$START_YMD)) -gt $((10#$END_YMD)) ]; then
    error_exit "Start date must be <= end date"
fi

for spec in "${REPO_SPECS[@]}"; do
    add_repo_spec "$spec"
done

mkdir -p "$OUTPUT_ROOT" "$WORK_ROOT"
OUTPUT_ROOT="$(cd "$OUTPUT_ROOT" && pwd)"
WORK_ROOT="$(cd "$WORK_ROOT" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$SCRIPT_DIR/m2a.sh" ]; then
    error_exit "m2a.sh not found in $SCRIPT_DIR"
fi

for i in "${!REPO_NAMES[@]}"; do
    name="${REPO_NAMES[$i]}"
    url="${REPO_URLS[$i]}"
    repo_dir="$WORK_ROOT/$name"
    repo_output="$OUTPUT_ROOT/$name"

    echo "开始处理仓库: $name"
    if [ -d "$repo_dir/.git" ]; then
        if ! update_repo "$repo_dir" "$url"; then
            echo "仓库远程地址不匹配，重新克隆: $name"
            safe_remove_repo "$repo_dir"
            git clone "$url" "$repo_dir"
        fi
    elif [ -e "$repo_dir" ]; then
        error_exit "Path exists but is not a git repo: $repo_dir"
    else
        git clone "$url" "$repo_dir"
    fi

    if [ ! -f "$repo_dir/m" ]; then
        error_exit "Missing m file in repo: $repo_dir"
    fi

    root_ymd=$(git -C "$repo_dir" log --reverse --format=%cd --date=format:%Y%m%d 2>/dev/null | head -1 || true)
    if [ -z "$root_ymd" ]; then
        error_exit "Failed to read earliest commit date from $repo_dir"
    fi

    if [ $((10#$START_YMD)) -le $((10#$root_ymd)) ]; then
        error_exit "Start date must be later than earliest commit ($root_ymd) for $repo_dir"
    fi

    checkout_end_commit "$repo_dir" "$END_YMD"

    if [ -z "$repo_output" ] || [ "$repo_output" = "/" ]; then
        error_exit "Unsafe output path: $repo_output"
    fi

    rm -rf "$repo_output"
    mkdir -p "$repo_output"

    (cd "$SCRIPT_DIR" && bash "$SCRIPT_DIR/m2a.sh" -o "$repo_output" -e "$START_YMD" -i "$repo_dir/m")
    echo "完成仓库: $name"

done

merge_outputs "$OUTPUT_ROOT" "$OUTPUT_ROOT/merged" "$MAX_SIZE"
