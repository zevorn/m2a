import os
import argparse
import shutil

def process_file(m_file_path, output_dir):
    old_filename = m_file_path  # 原文件路径（通过参数传入）
    # 确保输出目录存在
    os.makedirs(output_dir, exist_ok=True)

    # 月份缩写映射表
    month_map = {
        'Jan': '01', 'Feb': '02', 'Mar': '03', 'Apr': '04',
        'May': '05', 'Jun': '06', 'Jul': '07', 'Aug': '08',
        'Sep': '09', 'Oct': '10', 'Nov': '11', 'Dec': '12'
    }

    # 检查原文件是否存在
    if not os.path.exists(old_filename):
        print(f"错误：原文件 '{old_filename}' 不存在")
        return

    # 存储文件内容、编码及关键行信息
    all_lines = []
    used_encoding = None
    subject_line_index = -1
    subject_content = None
    date_content = None

    # 读取原文件并提取Subject和Date
    try:
        # 尝试utf-8编码
        with open(old_filename, 'r', encoding='utf-8') as f:
            all_lines = f.readlines()
            used_encoding = 'utf-8'

        # 查找Subject和Date行
        for i, line in enumerate(all_lines):
            stripped_line = line.lstrip()
            if stripped_line.startswith('Subject:') and not subject_content:
                subject_content = line.split(':', 1)[1].strip()
                subject_line_index = i
            if stripped_line.startswith('Date:') and not date_content:
                date_content = line.split(':', 1)[1].strip()

        # 若未找到，尝试gbk编码
        if not subject_content or not date_content:
            with open(old_filename, 'r', encoding='gbk') as f:
                all_lines = f.readlines()
                used_encoding = 'gbk'

            for i, line in enumerate(all_lines):
                stripped_line = line.lstrip()
                if stripped_line.startswith('Subject:') and not subject_content:
                    subject_content = line.split(':', 1)[1].strip()
                    subject_line_index = i
                if stripped_line.startswith('Date:') and not date_content:
                    date_content = line.split(':', 1)[1].strip()

    except Exception as e:
        print(f"读取原文件时出错：{e}")
        return

    # 检查关键行是否存在
    if subject_line_index == -1:
        print("未找到以 'Subject:' 开头的行，终止操作")
        return
    if not date_content:
        print("未找到以 'Date:' 开头的行，终止操作")
        return

    # 处理日期：生成纯数字格式（如20251027180020）
    try:
        raw_date = date_content.strip()
        if ',' in raw_date:
            raw_date = raw_date.split(',', 1)[1].strip()

        date_parts = raw_date.split()
        if len(date_parts) < 4:
            raise ValueError("日期格式不完整，无法解析")

        day, month_abbr, year, time_str = date_parts[0], date_parts[1], date_parts[2], date_parts[3]
        month = month_map.get(month_abbr, None)
        if not month:
            raise ValueError(f"无法识别的月份：{month_abbr}")

        day = day.zfill(2)
        time_parts = time_str.split(':')[:3]
        if len(time_parts) != 3:
            raise ValueError("时间格式不正确（需时:分:秒）")
        hour, minute, second = [p.zfill(2) for p in time_parts]
        second = second.split('.')[0]  # 移除秒后的小数部分

        formatted_date = f"{year}{month}{day}{hour}{minute}{second}"  # 纯数字日期
    except Exception as e:
        print(f"日期处理失败：{e}")
        return

    # 处理标题：过滤非法字符
    invalid_chars = '/\\:*?"<>|'
    for char in invalid_chars:
        subject_content = subject_content.replace(char, '_')
    subject_content = subject_content.strip()
    if not subject_content:
        subject_content = "无标题"

    # 生成新文件名（控制在80字符内）
    separator = "_"
    ext = ".txt"
    max_total_length = 80  # 总长度限制（含扩展名）
    max_body_length = max_total_length - len(ext)

    date_length = len(formatted_date)
    separator_length = len(separator)
    available_title_length = max_body_length - date_length - separator_length

    if available_title_length <= 0:
        combined_body = formatted_date
    else:
        truncated_title = subject_content[:available_title_length].rstrip(separator)
        combined_body = f"{formatted_date}{separator}{truncated_title}"

    new_filename = f"{combined_body}{ext}"
    # 拼接输出路径（输出目录 + 新文件名）
    new_file_path = os.path.join(output_dir, new_filename)

    # 检查新文件是否已存在
    if os.path.exists(new_file_path):
        print(f"警告：新文件 '{new_file_path}' 已存在，将覆盖")

    # 创建新文件并写入内容（仅保留Subject行及以下内容）
    try:
        # 提取Subject行及以下的内容作为新文件内容
        new_content = all_lines[subject_line_index:]
        with open(new_file_path, 'w', encoding=used_encoding) as f:
            f.writelines(new_content)
    except Exception as e:
        print(f"创建新文件时出错：{e}")
        return

if __name__ == "__main__":
    # 解析命令行参数
    parser = argparse.ArgumentParser(description='处理指定的m文件并生成新文件')
    parser.add_argument('-i', '--file', required=True, help='指定m文件的路径（例如：./m 或 /path/to/m）')
    parser.add_argument('-o', '--output', required=True, help='指定新文件的输出目录（例如：./output 或 /path/to/output）')
    args = parser.parse_args()

    # 调用处理函数（传入原文件路径和输出目录）
    process_file(args.file, args.output)