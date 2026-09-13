# 开发辅助：直接解析 .glb 的 JSON 块，打印节点/网格/骨骼/动画结构。
# 不依赖 Godot 导入，适合对比"旧模型 vs 新武器"的静止位置。
# 用法： pwsh -File tools/glb_info.ps1 <glb路径>
param([Parameter(Mandatory = $true)][string]$Path)

$bytes = [System.IO.File]::ReadAllBytes($Path)
$magic = [System.Text.Encoding]::ASCII.GetString($bytes, 0, 4)
if ($magic -ne 'glTF') { Write-Output "不是 GLB 文件 (magic=$magic)"; exit 1 }
$chunkLen = [System.BitConverter]::ToUInt32($bytes, 12)
$chunkType = [System.Text.Encoding]::ASCII.GetString($bytes, 16, 4)
if ($chunkType -ne 'JSON') { Write-Output "首个块不是 JSON (type=$chunkType)"; exit 1 }
$json = [System.Text.Encoding]::UTF8.GetString($bytes, 20, $chunkLen) | ConvertFrom-Json

Write-Output "=== $Path ==="
Write-Output "--- 节点 ---"
for ($i = 0; $i -lt $json.nodes.Count; $i++) {
    $n = $json.nodes[$i]
    $t = @()
    if ($n.translation) { $t += "T=($([math]::Round($n.translation[0],3)),$([math]::Round($n.translation[1],3)),$([math]::Round($n.translation[2],3)))" }
    if ($n.rotation)    { $t += "R=($([math]::Round($n.rotation[0],3)),$([math]::Round($n.rotation[1],3)),$([math]::Round($n.rotation[2],3)),$([math]::Round($n.rotation[3],3)))" }
    if ($n.scale)       { $t += "S=($($n.scale -join ','))" }
    $extra = @()
    if ($null -ne $n.mesh) { $extra += "mesh=$($n.mesh)" }
    if ($null -ne $n.skin) { $extra += "skin=$($n.skin)" }
    if ($n.children) { $extra += "children=[$($n.children -join ',')]" }
    Write-Output ("[{0}] {1}  {2}  {3}" -f $i, $n.name, ($t -join ' '), ($extra -join ' '))
}

Write-Output "--- 网格（POSITION 包围盒 = 网格空间顶点范围）---"
for ($i = 0; $i -lt $json.meshes.Count; $i++) {
    $m = $json.meshes[$i]
    foreach ($p in $m.primitives) {
        $acc = $json.accessors[$p.attributes.POSITION]
        $mn = ($acc.min | ForEach-Object { [math]::Round($_, 3) }) -join ', '
        $mx = ($acc.max | ForEach-Object { [math]::Round($_, 3) }) -join ', '
        Write-Output ("mesh[{0}] {1}: min=({2}) max=({3})" -f $i, $m.name, $mn, $mx)
    }
}

if ($json.skins) {
    Write-Output "--- 蒙皮 ---"
    for ($i = 0; $i -lt $json.skins.Count; $i++) {
        $s = $json.skins[$i]
        $jointNames = ($s.joints | ForEach-Object { $json.nodes[$_].name }) -join ', '
        Write-Output ("skin[{0}] name={1} 关节数={2}" -f $i, $s.name, $s.joints.Count)
        Write-Output ("   关节: {0}" -f $jointNames)
    }
}

if ($json.animations) {
    Write-Output "--- 动画 ---"
    for ($i = 0; $i -lt $json.animations.Count; $i++) {
        $a = $json.animations[$i]
        Write-Output ("anim[{0}] {1} 通道数={2}" -f $i, $a.name, $a.channels.Count)
    }
}
