#!/bin/bash

# 1. 设置要分析的目标目录 (如果不填，默认是当前目录下的 source)
TARGET_DIR="${1:-source}"

# 如果目录不存在，报错并退出
if [ ! -d "$TARGET_DIR" ]; then
    echo "错误：找不到目录 $TARGET_DIR"
    exit 1
fi

# 2. 创建一个临时文件，用来像记事本一样记录我们找到的依赖关系
DEP_FILE="dependency_list.txt"
> "$DEP_FILE" # 这行代码的意思是清空或创建一个空文件

echo "正在扫描文件并提取双引号 \"\" 中的依赖关系..."

# 3. 找到目录下所有的 .cpp 和 .h 文件，并逐个读取
find "$TARGET_DIR" -type f \( -name "*.cpp" -o -name "*.h" \) | while read -r filepath; do
    
    # basename 命令可以把又长又臭的路径去掉，只保留文件名
    # 比如把 a/b/c/main.cpp 变成 main.cpp
    filename=$(basename "$filepath")
    
    # 把这个文件记录到我们的“记事本”里，证明它存在 (FILE 代表文件)
    echo "FILE $filename" >> "$DEP_FILE"
    
    # ================= 核心修改在这里 =================
    # 这一步专门用来提取 #include "xxx.h" 里的 xxx.h
    # grep -E ... : 找到包含 #include 并且后面跟着双引号的行
    # cut -d'"' -f2 : 以双引号为刀把句子切开，取第2段（也就是文件名）
    # awk -F'/' '{print $NF}' : 如果名字带有路径 (如 dir/a.h)，只取最后的文件名 (a.h)
    includes=$(grep -E '^[[:space:]]*#[[:space:]]*include[[:space:]]+"[^"]+"' "$filepath" | cut -d'"' -f2 | awk -F'/' '{print $NF}')
    
    # 把找到的依赖关系一行行写进“记事本” (DEP 代表依赖)
    for inc_file in $includes; do
        echo "DEP $filename $inc_file" >> "$DEP_FILE"
    done
done

echo "扫描完成！正在计算每个文件的深度..."

# 4. 使用 awk 读取我们刚才写好的“记事本”，进行简单的数学计算
awk '
    # (1) 读取数据阶段
    # 遇到 FILE 开头的行，记录下这个名字
    /^FILE/ { all_files[$2] = 1 }
    # 遇到 DEP 开头的行，把依赖关系用空格拼接起来
    # 比如 a.cpp 依赖 b.h 和 c.h，就会变成 depends_on["a.cpp"] = "b.h c.h"
    /^DEP/  { depends_on[$2] = depends_on[$2] " " $3 }

    # (2) 计算深度的核心函数
    function calculate_depth(file_name) {
        # 如果这个文件之前算过了，直接交答案，不重复劳动
        if (file_name in depth_record) return depth_record[file_name]

        # 检查死循环：如果 A 包含 B，B 又包含 A，直接当作深度 0 处理并退出
        if (is_calculating[file_name]) return 0
        is_calculating[file_name] = 1

        # 如果这个文件什么都没依赖（或者依赖的东西在项目里找不到）
        # 那么它的深度就是 0
        if (depends_on[file_name] == "") {
            depth_record[file_name] = 0
            return 0
        }

        # 如果它有依赖，那么它的深度 = 它依赖的文件里“最深”的那个 + 1
        max_child_depth = -1
        
        # 把刚才拼接的 "b.h c.h" 拆成数组
        num_deps = split(depends_on[file_name], dep_array, " ")
        
        # 挨个问它依赖的文件：你的深度是多少？
        for (i = 1; i <= num_deps; i++) {
            child_depth = calculate_depth(dep_array[i])
            # 找出最大值
            if (child_depth > max_child_depth) {
                max_child_depth = child_depth
            }
        }
        
        # 记录下自己的深度：最大子深度 + 1
        depth_record[file_name] = max_child_depth + 1
        return depth_record[file_name]
    }

    # (3) 所有数据读完后，开始公布结果
    END {
        global_max_depth = -1
        
        # 先把所有文件的深度算一遍，顺便找出全局最大值
        for (f in all_files) {
            d = calculate_depth(f)
            if (d > global_max_depth) {
                global_max_depth = d
            }
        }

        print "\n================ 分析结果 ================"
        print "【1. 深度最大的文件 (最大深度: " global_max_depth ") 】"
        for (f in all_files) {
            if (depth_record[f] == global_max_depth) {
                print "- " f
            }
        }

        print "\n【2. 叶子文件 (深度为 0，即不依赖任何其他文件的文件) 】"
        for (f in all_files) {
            if (depth_record[f] == 0) {
                print "- " f
            }
        }
        print "=========================================="
    }
' "$DEP_FILE"

# 5. 打扫战场：删掉临时生成的记事本文件
rm "$DEP_FILE"
