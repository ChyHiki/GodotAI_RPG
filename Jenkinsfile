// Godot 项目 CI：GitHub 拉代码 -> headless 冒烟 -> headless 主测试
// 测试入口与断言数量见 README「自动化测试」章节
pipeline {
    agent any

    options {
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '30'))
        disableConcurrentBuilds()
    }

    triggers {
        // 每 5 分钟问一次 GitHub，main 有新提交就自动构建（H 前缀让负载分散）
        pollSCM('H/5 * * * *')
    }

    environment {
        // Godot 4.7.2 控制台版，--headless 需要它才能拿到 stdout 与退出码
        GODOT = 'D:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe'
    }

    stages {
        stage('环境检查') {
            steps {
                sh '''
                    echo "工作区: $(pwd)"
                    echo "提交:   $(git log -1 --pretty='%h %s')"
                    if [ ! -f "$GODOT" ]; then
                        echo "找不到 Godot 可执行文件: $GODOT"
                        exit 1
                    fi
                    "$GODOT" --version
                    echo "Godot 版本检查通过"
                '''
            }
        }

        stage('资源导入') {
            steps {
                // 必须有这一步：干净克隆没有 .godot 缓存，直接跑脚本会因 class_name 未注册而大面积解析失败
                // （Could not find type "Npc" / "Hud" / "PlayerCharacter" ...）。--import 会建立全局类缓存
                sh '"$GODOT" --headless --path . --import'
            }
        }

        stage('冒烟测试（240 帧）') {
            steps {
                sh '"$GODOT" --headless --path . --quit-after 240'
            }
        }

        stage('主测试（339 项断言）') {
            steps {
                sh '"$GODOT" --headless --path . res://tools/autotest/m1_autotest.tscn'
            }
        }
    }

    post {
        success {
            echo '全部测试通过'
        }
        failure {
            echo '测试失败：看上方哪个 stage 报非 0 退出码，再往上翻断言明细'
        }
    }
}
