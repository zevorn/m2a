#!/bin/bash

# 初始化变量
dir_name=""
end_ym=""
m_file_path=""  # m文件路径
m_dir_path=""   # m文件所在文件夹路径
MAX_SIZE=$((8 * 1024 * 1024))  # 8MiB

# 解析命令行选项
while getopts "o:e:i:" opt; do
    case $opt in
        o) dir_name="$OPTARG" ;;
        e) end_ym="$OPTARG" ;;
        i) m_file_path="$OPTARG" ;;  # 接收m文件路径
        \?) echo "错误：无效的选项 -$OPTARG" >&2; exit 1 ;;
        :) echo "错误：选项 -$OPTARG 需要提供参数" >&2; exit 1 ;;
    esac
done

# 检查必要参数是否提供
if [ -z "$dir_name" ] || [ -z "$end_ym" ] || [ -z "$m_file_path" ]; then
    echo "用法: $0 -f <文件夹名称> -e <结束日期(格式：YYYYMM)> -i <m文件的路径>"
    echo "示例: $0 -f qemu-devel-email -e 202501 -i ./m （处理指定路径的m文件）"
    exit 1
fi

# 验证m文件是否存在
if [ ! -f "$m_file_path" ]; then
    echo "错误：指定的m文件 '$m_file_path' 不存在或不是文件" >&2
    exit 1
fi

# 提取m文件所在的文件夹路径
m_dir_path=$(dirname "$m_file_path")
echo "检测到m文件所在文件夹: $m_dir_path"

# 验证该文件夹是否是git仓库
if [ ! -d "$m_dir_path/.git" ]; then
    echo "警告：m文件所在文件夹 '$m_dir_path' 不是git仓库，可能导致git操作失败" >&2
fi

# 验证结束日期格式
if ! [[ $end_ym =~ ^[0-9]{6}$ ]]; then
    echo "错误：结束日期必须是6位数字（格式YYYYMM，例如202501）" >&2
    exit 1
fi

# 提取月份部分验证有效性
month="${end_ym:4:2}"
if [ "$month" -lt 1 ] || [ "$month" -gt 12 ]; then
    echo "错误：月份必须在01-12之间（输入的月份为$month）" >&2
    exit 1
fi

echo "开始处理，将持续执行直到遇到早于 $end_ym 的文件..."
echo "目标文件夹: $dir_name"
echo "使用的m文件路径: $m_file_path"
echo "合并文件最大限制: 8MiB"
echo "----------------------------------------"

loop_num=1  # 循环计数器
stop_flag=0  # 停止标志

# 持续循环处理
while [ $stop_flag -eq 0 ]; do

    # 1. 执行format.py生成文件，输出到m文件的同级目录
    if ! python format.py -i "$m_file_path" -o "$m_dir_path"; then
        echo "错误：python format.py 执行失败（使用m文件：$m_file_path）" >&2
        exit 1
    fi
    
    # 2. 回退git提交（指定m所在文件夹）
    if ! git -C "$m_dir_path" reset --hard HEAD~1; then
        echo "错误：在仓库 '$m_dir_path' 执行 git reset --hard HEAD~1 失败" >&2
        exit 1
    fi
    
    # 3. 处理生成的目标文件（从m的同级目录查找）
    file_count=0
    # 构建目标文件的通配符路径（m所在目录下的txt文件）
    target_files_pattern="$m_dir_path/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_*.txt"
    
    for file in $target_files_pattern; do
        # 跳过不存在的文件
        [ -f "$file" ] || continue
        
        ((file_count++))
        
        # 提取文件名（仅文件名，不含路径）
        filename=$(basename "$file")
        # 提取文件名中的年月（前6位）
        file_ym="${filename:0:6}"
        
        # 检查是否需要停止
        if [ "$file_ym" -lt "$end_ym" ]; then
            echo "→ 检测到文件年月 $file_ym 早于结束日期 $end_ym，将在本轮处理后停止"
            stop_flag=1
        fi
        
        # 创建目标文件夹并移动文件（从m所在目录移动到目标目录）
        target_dir="$dir_name/$file_ym"
        mkdir -p "$target_dir"
        mv "$file" "$target_dir/" || {
            echo "错误：无法移动文件 $file 到 $target_dir" >&2
            exit 1
        }
        
        # 获取移动后的文件路径
        moved_file="$target_dir/$filename"
        
        # 4. 合并文件到年月_编号.txt
        last_file=$(ls -v "$target_dir"/"$file_ym"_*.txt 2>/dev/null | tail -1)
        
        if [ -z "$last_file" ]; then
            current_num=1
            target_file="$target_dir/${file_ym}_${current_num}.txt"
            cp "$moved_file" "$target_file" || {
                echo "错误：无法创建合并文件 $target_file" >&2
                exit 1
            }
        else
            last_size=$(stat -c "%s" "$last_file")
            
            if [ "$last_size" -lt "$MAX_SIZE" ]; then
                target_file="$last_file"
                cat "$moved_file" >> "$target_file" || {
                    echo "错误：无法追加内容到 $target_file" >&2
                    exit 1
                }
            else
                current_num=$(echo "$last_file" | grep -oP "${file_ym}_\K\d+" | awk '{print $1 + 1}')
                target_file="$target_dir/${file_ym}_${current_num}.txt"
                cp "$moved_file" "$target_file" || {
                    echo "错误：无法创建新合并文件 $target_file" >&2
                    exit 1
                }
            fi
        fi
        
        # 删除已合并的源文件
        rm -f "$moved_file" || {
            echo "错误：无法删除已合并的文件 $moved_file" >&2
            exit 1
        }
        # echo "$moved_file → $target_file"
    done
    
    if [ $stop_flag -eq 1 ]; then
        break
    fi
    
    ((loop_num++))
done

echo "----------------------------------------"
echo "处理结束（已遇到早于 $end_ym 的文件）"
echo "文件已保存至: $dir_name"
echo "合并文件格式: YYYYMM_编号.txt（单个文件不超过8MiB）"