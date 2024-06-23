#!/bin/bash

# クリーンアップ用関数
cleanup() {
    [[ -f $temp_file ]] && rm -f "$temp_file"
}
trap cleanup EXIT

# iniファイルを読み込んで連想配列に格納する関数
ini_parse() {
    local ini_file=$1
    declare -n ini_data=$2

    if [[ ! -f $ini_file ]]; then
        echo "Error: File '$ini_file' not found." >&2
        return 1
    fi

    local section=""
    local line_number=0

    while IFS= read -r line || [ -n "$line" ]; do
        ((line_number++))
        line=$(echo "$line" | sed 's/^[ \t]*//;s/[ \t]*$//') # 空白をトリム

        if [[ $line =~ ^\[([^\]]*)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            # セクション名に `[` または `]` を含めない
            if [[ $section == *"["* || $section == *"]"* ]]; then
                echo "Error: Section name '$section' contains '[' or ']' at $ini_file:$line_number" >&2
                return 1
            fi
        elif [[ $line =~ ^[;#] || -z $line ]]; then
            continue
        elif [[ $line =~ ^([^=]+)=(.*)$ ]]; then
            local key=$(echo "${BASH_REMATCH[1]}" | sed 's/^[ \t]*//;s/[ \t]*$//')
            local value=$(echo "${BASH_REMATCH[2]}" | sed 's/^[ \t]*//;s/[ \t]*$//')
            ini_data["[$section]$key"]="$value"
        else
            echo "Error: Invalid line at $ini_file:$line_number: $line" >&2
            return 1
        fi
    done < "$ini_file"
}

# セクションとオプションの値を取得する関数
ini_get() {
    declare -n ini_data=$3
    local section=$1
    local option=$2
    local value="${ini_data["[$section]$option"]}"
    if [[ -z $value ]]; then
        echo "Error: Section '$section' or option '$option' not found." >&2
        return 1
    fi
    echo "$value"
}

# セクションとオプションの値を設定する関数
ini_set() {
    declare -n ini_data=$4
    local section=$1
    local option=$2
    local value=$3
    if [[ -z $section || -z $option ]]; then
        echo "Error: Section and option must be provided." >&2
        return 1
    fi
    if [[ $section == *"["* || $section == *"]"* ]]; then
        echo "Error: Section name '$section' contains '[' or ']'" >&2
        return 1
    fi
    ini_data["[$section]$option"]="$value"
}

# セクションとオプションの値を削除する関数
ini_remove() {
    declare -n ini_data=$3
    local section=$1
    local option=$2
    if [[ -z $section || -z $option ]]; then
        echo "Error: Section and option must be provided." >&2
        return 1
    fi
    unset ini_data["[$section]$option"]
}

# セクション全体を削除する関数
ini_remove_section() {
    declare -n ini_data=$2
    local section=$1
    if [[ -z $section ]]; then
        echo "Error: Section must be provided." >&2
        return 1
    fi
    for key in "${!ini_data[@]}"; do
        if [[ $key == "[$section]"* ]]; then
            unset ini_data["$key"]
        fi
    done
}

# 指定されたセクションのオプションをリスト表示する関数
ini_list_options() {
    declare -n ini_data=$2
    local section=$1
    if [[ -z $section ]]; then
        echo "Error: Section must be provided." >&2
        return 1
    fi
    local options=()
    for key in "${!ini_data[@]}"; do
        if [[ $key == "[$section]"* ]]; then
            options+=("${key#*\]}")
        fi
    done
    echo "${options[@]}"
}

# 指定されたセクションが存在するか確認する関数
ini_has_section() {
    declare -n ini_data=$2
    local section=$1
    if [[ -z $section ]]; then
        echo "Error: Section must be provided." >&2
        return 1
    fi
    for key in "${!ini_data[@]}"; do
        if [[ $key == "[$section]"* ]]; then
            return 0
        fi
    done
    return 1
}

# 指定されたセクションとオプションが存在するか確認する関数
ini_has_option() {
    declare -n ini_data=$3
    local section=$1
    local option=$2
    if [[ -z $section || -z $option ]]; then
        echo "Error: Section and option must be provided." >&2
        return 1
    fi
    if [[ -n ${ini_data["[$section]$option"]} ]]; then
        return 0
    else
        return 1
    fi
}

# iniファイルに保存する関数
ini_save() {
    declare -n ini_data=$2
    local ini_file=$1
    local temp_file=$(mktemp) || { echo "Error: Unable to create temp file." >&2; return 1; }

    local section=""

    while IFS= read -r line || [ -n "$line" ]; do
        if [[ $line =~ ^\[([^\]]*)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            if ! ini_has_section "$section" ini_data; then
                continue
            fi
            echo "$line" >> "$temp_file"
        elif [[ $line =~ ^[;#] || -z $line ]]; then
            echo "$line" >> "$temp_file"
        elif [[ $line =~ ^([^=]+)=(.*)$ ]]; then
            local key=$(echo "${BASH_REMATCH[1]}" | sed 's/^[ \t]*//;s/[ \t]*$//')
            if ! ini_has_section "$section" ini_data; then
                continue
            fi
            local value="${ini_data["[$section]$key"]}"
            if [[ -n $value ]]; then
                echo "$key=$value" >> "$temp_file"
                unset ini_data["[$section]$key"]
            else
                if ! ini_has_option "$section" "$key" ini_data; then
                    echo "$line" >> "$temp_file"
                fi
            fi
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$ini_file"

    # 追加のセクションとオプションを追加
    local sections=$(ini_list_sections ini_data)
    for section in $sections; do
        if ! ini_has_section "$section" ini_data; then
            continue
        fi
        echo "[$section]" >> "$temp_file"
        for key in "${!ini_data[@]}"; do
            if [[ $key == "[$section]"* ]]; then
                local option=${key#*\]}
                echo "$option=${ini_data[$key]}" >> "$temp_file"
                unset ini_data["$key"]
            fi
        done
    done

    mv "$temp_file" "$ini_file" || { echo "Error: Unable to move temp file to $ini_file." >&2; return 1; }
}

# セクションを取得する関数
ini_list_sections() {
    declare -n ini_data=$1
    local sections=()
    for key in "${!ini_data[@]}"; do
        local section=${key%%\]*}
        section=${section#\[}
        if [[ ! " ${sections[*]} " =~ " ${section} " ]]; then
            sections+=("$section")
        fi
    done
    echo "${sections[@]}"
}
