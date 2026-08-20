param(
    [string]$ScenePath = "scenes/New_Level.tscn",
    [double]$Factor = 1.25
)

$ErrorActionPreference = "Stop"
$fullPath = (Resolve-Path -LiteralPath $ScenePath).Path
$lines = [System.Collections.Generic.List[string]](Get-Content -LiteralPath $fullPath)
if ($lines -match '^metadata/longitudinal_spacing_expanded = true$') {
    throw "New_Level longitudinal spacing has already been expanded."
}

function Format-Number([double]$value) {
    return $value.ToString("0.########", [Globalization.CultureInfo]::InvariantCulture)
}

function Rewrite-OriginZ([string]$line, [scriptblock]$operation) {
    if ($line -notmatch '^transform = Transform3D\((.*)\)$') { return $line }
    $parts = $matches[1].Split(',')
    if ($parts.Count -ne 12) { throw "Unexpected Transform3D: $line" }
    $z = [double]::Parse($parts[11].Trim(), [Globalization.CultureInfo]::InvariantCulture)
    $parts[11] = " " + (Format-Number (& $operation $z))
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

    # 独立资产根只改变Z坐标，货架basis与白盒尺寸保持原样。
    if ($nodeParent -in @('ShelfIslands', 'GameplayMarkers',
            'RuntimeOnly/WaitingRoomLighting', 'RuntimeOnly/AisleLighting')) {
        $lines[$i] = Rewrite-OriginZ $line { param($z) $z * $Factor }
        continue
    }
    if ($nodeParent -eq 'CheckoutZone' -and
            ($nodeName -in @('CheckoutGroup_North', 'CheckoutGroup_South') -or
             $nodeName -like 'CheckoutLaneGuide_*')) {
        $lines[$i] = Rewrite-OriginZ $line { param($z) $z * $Factor }
        continue
    }

    # 平级组成的壁柜/售货机按整件资产平移，避免外壳与玻璃/屏幕被拉开。
    if ($nodeParent -eq 'PerimeterCases') {
        $delta = 0.0
        if ($nodeName -match 'WallCase_[WE]_North_') { $delta = -14.890925 * ($Factor - 1.0) }
        elseif ($nodeName -match 'WallCase_[WE]_South_') { $delta = 14.890925 * ($Factor - 1.0) }
        elseif ($nodeName -match '^Vending_N[WE]') { $delta = -21.56 * ($Factor - 1.0) }
        elseif ($nodeName -match '^Vending_S[WE]') { $delta = 21.56 * ($Factor - 1.0) }
        if ([Math]::Abs($delta) -gt 0.00001) {
            $lines[$i] = Rewrite-OriginZ $line { param($z) $z + $delta }
        }
        continue
    }

    # 四面吊牌以各分区中心为单位整体平移，文字仍贴在厚重牌体四周。
    if ($nodeParent -eq 'HangingZoneSigns') {
        $center = 0.0
        if ($nodeName -match '_(Fresh|Frozen)(_|$)') { $center = -14.0 }
        elseif ($nodeName -match '_(Beauty)(_|$)') { $center = -15.0 }
        elseif ($nodeName -match '_(Snacks|Clothing)(_|$)') { $center = 14.0 }
        elseif ($nodeName -match '_(Daily)(_|$)') { $center = 15.0 }
        $delta = $center * ($Factor - 1.0)
        if ([Math]::Abs($delta) -gt 0.00001) {
            $lines[$i] = Rewrite-OriginZ $line { param($z) $z + $delta }
        }
    }
}

$markerIndex = $lines.FindIndex({ param($line) $line -match '^metadata/longitudinal_expansion = ' })
if ($markerIndex -lt 0) { throw "Missing longitudinal_expansion metadata." }
$lines.Insert($markerIndex + 1, 'metadata/longitudinal_spacing_expanded = true')
[IO.File]::WriteAllLines($fullPath, $lines, [Text.UTF8Encoding]::new($false))
Write-Output "Expanded New_Level Z spacing by $Factor without scaling shelf asset bases."
