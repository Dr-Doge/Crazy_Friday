<#
.SYNOPSIS
	使用New_Level场景内的正交审查相机生成俯视排布截图。
.DESCRIPTION
	只用于对照 images/黑五扫货_超市施工指示图_v6_2K.png。
	运行时自动隐藏HUD、角色、商品、天花板和灯具，不改变正常对局。
#>
[CmdletBinding()]
param(
	[string]$Output = '',
	[string]$Godot = ''
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
if (-not $Output) {
	$Output = Join-Path $ProjectRoot 'test_out\new_level_topdown.png'
}
$Output = [System.IO.Path]::GetFullPath($Output)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Output) | Out-Null
if (Test-Path -LiteralPath $Output) {
	Remove-Item -LiteralPath $Output -Force
}

if (-not $Godot) {
	if ($env:GODOT_BIN -and (Test-Path -LiteralPath $env:GODOT_BIN)) {
		$Godot = $env:GODOT_BIN
	} else {
		$roots = @("$env:USERPROFILE\Desktop", "$env:USERPROFILE\Downloads")
		$Godot = Get-ChildItem -Path $roots -Filter 'Godot*.exe' -File -Recurse -Depth 3 -ErrorAction SilentlyContinue |
			Where-Object { $_.Length -gt 50MB -and $_.Name -match 'v4\.7' } |
			Sort-Object @{ Expression = { if ($_.Name -match '4\.7\.1') { 0 } else { 1 } } } |
			Select-Object -First 1 -ExpandProperty FullName
	}
}
if (-not $Godot -or -not (Test-Path -LiteralPath $Godot)) {
	throw '未找到Godot 4.7可执行文件；请用-Godot指定。'
}

$oldAuto = $env:WHITEBOX_AUTOSTART
$oldNpc = $env:WHITEBOX_NPC
$oldShot = $env:WHITEBOX_TOPDOWN_SHOT
try {
	$env:WHITEBOX_AUTOSTART = '1'
	$env:WHITEBOX_NPC = '0'
	$env:WHITEBOX_TOPDOWN_SHOT = $Output
	& $Godot --path $ProjectRoot --resolution 1600x1000
	# Windows GUI版Godot成功退出时可能不设置LASTEXITCODE；只有明确的非零值才判错。
	if ($null -ne $LASTEXITCODE -and $LASTEXITCODE -ne 0) {
		throw "Godot俯视截图失败，退出码$LASTEXITCODE"
	}
	# GUI版可能在启动子进程后提前把控制权交还PowerShell，给截图钩子最多15秒落盘。
	for ($i = 0; $i -lt 75 -and -not (Test-Path -LiteralPath $Output); $i++) {
		Start-Sleep -Milliseconds 200
	}
	if (-not (Test-Path -LiteralPath $Output)) {
		throw "未生成俯视截图：$Output"
	}
	Write-Host "俯视排布截图：$Output"
} finally {
	$env:WHITEBOX_AUTOSTART = $oldAuto
	$env:WHITEBOX_NPC = $oldNpc
	$env:WHITEBOX_TOPDOWN_SHOT = $oldShot
}
