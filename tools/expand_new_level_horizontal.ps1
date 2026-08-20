param(
    [string]$ScenePath = "scenes/New_Level.tscn",
    [double]$Factor = 1.25
)

$ErrorActionPreference = "Stop"
$fullPath = (Resolve-Path -LiteralPath $ScenePath).Path
$lines = [System.Collections.Generic.List[string]](Get-Content -LiteralPath $fullPath)
if ($lines -match '^metadata/horizontal_spacing_expanded = true$') {
    throw "New_Level horizontal spacing has already been expanded."
}

function Format-Number([double]$value) {
    return $value.ToString("0.########", [Globalization.CultureInfo]::InvariantCulture)
}

function Rewrite-OriginX([string]$line, [scriptblock]$operation) {
    if ($line -notmatch '^transform = Transform3D\((.*)\)$') { return $line }
    $parts = $matches[1].Split(',')
    if ($parts.Count -ne 12) { throw "Unexpected Transform3D: $line" }
    $x = [double]::Parse($parts[9].Trim(), [Globalization.CultureInfo]::InvariantCulture)
    $parts[9] = " " + (Format-Number (& $operation $x))
    return "transform = Transform3D(" + ($parts -join ',') + ")"
}

$nodeName = ""
$nodeParent = ""
for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ($line -match '^\[node name="([^"]+)" type="[^"]+" parent="([^"]+)"') {
        $nodeName = $matches[1]
        $nodeParent = $matches[2]
        continue
    }
    if ($line -match '^\[node name="([^"]+)" type="[^"]+"') {
        $nodeName = $matches[1]
        $nodeParent = "."
        continue
    }
    if ($line -notmatch '^transform = Transform3D') { continue }

    # 货架、玩法标记和灯具都是独立资产根：只拉开X坐标，不改变basis/模型大小。
    if ($nodeParent -in @('ShelfIslands', 'GameplayMarkers',
            'RuntimeOnly/WaitingRoomCeilings', 'RuntimeOnly/WaitingRoomLighting',
            'RuntimeOnly/AisleLighting')) {
        $lines[$i] = Rewrite-OriginX $line { param($x) $x * $Factor }
        continue
    }
    if ($nodeParent -eq 'CheckoutZone' -and $nodeName -in @('CheckoutGroup_West', 'CheckoutGroup_East')) {
        $lines[$i] = Rewrite-OriginX $line { param($x) $x * $Factor }
        continue
    }

    # 壁柜/贩卖机的外壳与玻璃、屏幕是同一资产的平级节点，必须使用相同位移，
    # 否则分别缩放坐标会拉开它们的内部装配关系。
    if ($nodeParent -eq 'PerimeterCases') {
        $delta = 0.0
        if ($nodeName -like 'WallCase_W_*') { $delta = -32.946915 * ($Factor - 1.0) }
        elseif ($nodeName -like 'WallCase_E_*') { $delta = 32.946915 * ($Factor - 1.0) }
        elseif ($nodeName -like 'Vending_NW*' -or $nodeName -like 'Vending_SW*') { $delta = -7.0 * ($Factor - 1.0) }
        elseif ($nodeName -like 'Vending_NE*' -or $nodeName -like 'Vending_SE*') { $delta = 7.0 * ($Factor - 1.0) }
        if ([Math]::Abs($delta) -gt 0.00001) {
            $lines[$i] = Rewrite-OriginX $line { param($x) $x + $delta }
        }
        continue
    }

    # 四面吊牌同样由多个平级节点组成：按分区中心整体平移，保持文字贴住方块四面。
    if ($nodeParent -eq 'HangingZoneSigns') {
        $delta = 0.0
        if ($nodeName -match '_(Fresh|Toys|Snacks)(_|$)') { $delta = -22.0 * ($Factor - 1.0) }
        elseif ($nodeName -match '_(Frozen|Electronics|Clothing)(_|$)') { $delta = 22.0 * ($Factor - 1.0) }
        if ([Math]::Abs($delta) -gt 0.00001) {
            $lines[$i] = Rewrite-OriginX $line { param($x) $x + $delta }
        }
    }
}

$markerIndex = $lines.FindIndex({ param($line) $line -match '^metadata/horizontal_expansion = ' })
if ($markerIndex -lt 0) { throw "Missing horizontal_expansion metadata." }
$lines.Insert($markerIndex + 1, 'metadata/horizontal_spacing_expanded = true')
[IO.File]::WriteAllLines($fullPath, $lines, [Text.UTF8Encoding]::new($false))
Write-Output "Expanded New_Level X spacing by $Factor without scaling shelf asset bases."
