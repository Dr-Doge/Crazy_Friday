<#
.SYNOPSIS
	《疯抢星期五》无头自动化冒烟测试。

.DESCRIPTION
	对应 策划方案集/12-版本沿革与验证记录.md 第三节沉淀的质量流程:
	  · 无头全场模拟   每次改动跑完整对局(打烊/宽限/结算),stderr 零容忍
	  · 联机多实例自动化  1主机 + N客户端满员冒烟,座位/种子/同步全链路核验

	判定标准(任一不满足即 FAIL):
	  1. 进程退出码为 0
	  2. stderr 完全为空(Godot 的脚本报错、断言、资源警告都会进 stderr)
	  3. stdout 出现该模式期望的里程碑(见各模式的 Expect)

.PARAMETER Mode
	single    单机对局(默认)
	tutorial  教学关九步
	mp        局域网联机:1 主机 + -Clients 个客户端
	all       依次跑上面三种

.PARAMETER Full
	跑完整 5 分钟 + 30 秒宽限(约 20400 帧),会真正走到打烊结算。
	不加此开关时只跑 1800 帧(30 秒游戏时间)的快速冒烟。

.EXAMPLE
	pwsh tools/smoke_test.ps1
	pwsh tools/smoke_test.ps1 -Mode single -Full
	pwsh tools/smoke_test.ps1 -Mode mp -Clients 5
	pwsh tools/smoke_test.ps1 -Mode all
#>
[CmdletBinding()]
param(
	[ValidateSet('single', 'tutorial', 'mp', 'phys', 'char', 'all')]
	[string]$Mode = 'single',

	[ValidateRange(1, 5)]
	[int]$Clients = 1,

	[switch]$Full,

	[int]$Frames = 0,

	# Godot 可执行文件。留空则自动探测(优先 console 版,否则 stdout/stderr 抓不到)
	[string]$Godot = ''
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$OutDir = Join-Path $ProjectRoot 'test_out'
$QUICK_FRAMES = 1800     # 快速冒烟:约 15 秒
$FULL_GUARD_FRAMES = 200000  # 全场模式的兜底帧数(正常由 WHITEBOX_QUIT_ON_END 提前退出)
$FULL_TIMEOUT_SEC = 600# 全场对局 = 5分钟 + 30秒宽限,真实耗时约 5.5 分钟
$MP_FRAMES = 2400        # 联机:够走完大厅→开局→同步

# ---------------------------------------------------------------- 环境准备

function Find-Godot {
	if ($Godot) {
		if (-not (Test-Path $Godot)) { throw "指定的 Godot 不存在: $Godot" }
		return (Resolve-Path $Godot).Path
	}
	if ($env:GODOT_BIN -and (Test-Path $env:GODOT_BIN)) { return $env:GODOT_BIN }

	$roots = @($env:USERPROFILE, "$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop") |
		Where-Object { $_ -and (Test-Path $_) }
	# 优先选择 project.godot 声明的引擎系列,再优先 console 版。
	# 旧实现直接取文件系统扫描到的第一个 console.exe,本机同时装有4.6/4.7时
	# 会悄悄用4.6跑绿,无法证明目标基线4.7真的通过。
	$requiredVersion = '4.7'
	$projectFile = Join-Path $ProjectRoot 'project.godot'
	if (Test-Path $projectFile) {
		$projectText = Get-Content -LiteralPath $projectFile -Raw -Encoding UTF8
		if ($projectText -match 'config/features=PackedStringArray\("([0-9]+\.[0-9]+)"') {
			$requiredVersion = $Matches[1]
		}
	}
	$candidates = @(
		Get-ChildItem -Path $roots -Filter 'Godot*_console.exe' -File -Recurse -Depth 3 -ErrorAction SilentlyContinue |
			# console.exe 只是启动器，必须有同目录同名的主程序；残缺解压目录不能入选。
			Where-Object {
				$mainName = $_.Name -replace '_console\.exe$', '.exe'
				Test-Path -LiteralPath (Join-Path $_.DirectoryName $mainName) -PathType Leaf
			}
	)
	$candidates += @(
		Get-ChildItem -Path $roots -Filter 'Godot*.exe' -File -Recurse -Depth 3 -ErrorAction SilentlyContinue |
			Where-Object { $_.Length -gt 50MB }
	)
	$versionPattern = 'v' + [regex]::Escape($requiredVersion) + '([.-]|$)'
	$found = $candidates | Sort-Object `
		@{ Expression = { if ($_.Name -match $versionPattern) { 0 } else { 1 } } }, `
		@{ Expression = { if ($_.Name -like '*_console.exe') { 0 } else { 1 } } }, `
		@{ Expression = { $_.LastWriteTime }; Descending = $true } |
		Select-Object -First 1
	if (-not $found) {
		throw "未找到 Godot 可执行文件。请用 -Godot <路径> 指定,或设置环境变量 GODOT_BIN。"
	}
	return $found.FullName
}

function Get-LocalIp {
	$ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
		Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
		Select-Object -First 1 -ExpandProperty IPAddress
	if($ip) { return $ip }
	return '127.0.0.1'
}

# ---------------------------------------------------------------- 实例调度

function Start-Instance {
	param(
		[string]$Name,
		[hashtable]$EnvVars,
		[int]$FrameCount
	)
	# Start-Process 继承调用时刻的会话环境,故"设值→立即启动→清理"是安全的
	foreach ($k in $EnvVars.Keys) { Set-Item -Path "env:$k" -Value $EnvVars[$k] }
	try {
		$out = Join-Path $OutDir "$Name.out.txt"
		$err = Join-Path $OutDir "$Name.err.txt"
		$proc = Start-Process -FilePath $script:godotBin `
			-ArgumentList '--headless', '--path', $ProjectRoot, '--quit-after', $FrameCount `
			-NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
		# 必须在进程退出前触碰 Handle,否则退出后 ExitCode 取不到值(PowerShell 已知陷阱)
		$null = $proc.Handle
		return [pscustomobject]@{ Name = $Name; Proc = $proc; Out = $out; Err = $err }
	}
	finally {
		foreach ($k in $EnvVars.Keys) { Remove-Item -Path "env:$k" -ErrorAction SilentlyContinue }
	}
}

function Test-Instance {
	param($Instance, [string[]]$Expect)

	$problems = @()
	if ($Instance.Proc.ExitCode -ne 0) {
		$problems += "退出码 $($Instance.Proc.ExitCode)"
	}
	$errText = ''
	if (Test-Path $Instance.Err) {
		$errText = (Get-Content -LiteralPath $Instance.Err -Raw -Encoding UTF8)
	}
	if ($errText -and $errText.Trim()) {
		$firstLines = ($errText.Trim() -split "`r?`n" | Select-Object -First 4) -join ' | '
		$problems += "stderr 非空: $firstLines"
	}
	$outText = ''
	if (Test-Path $Instance.Out) {
		$outText = (Get-Content -LiteralPath $Instance.Out -Raw -Encoding UTF8)
	}
	foreach ($token in $Expect) {
		if ($outText -notmatch [regex]::Escape($token)) {
			$problems += "stdout 缺少里程碑 '$token'"
		}
	}
	return [pscustomobject]@{
		Name = $Instance.Name
		Passed = ($problems.Count -eq 0)
		Problems = $problems
	}
}

function Wait-Instances {
	param($Instances, [int]$TimeoutSec)
	$deadline = (Get-Date).AddSeconds($TimeoutSec)
	foreach ($i in $Instances) {
		$remain = [int]($deadline - (Get-Date)).TotalSeconds
		if ($remain -lt 1) { $remain = 1 }
		if (-not $i.Proc.WaitForExit($remain * 1000)) {
			Write-Warning "$($i.Name) 超时未退出,强制结束"
			try { $i.Proc.Kill() } catch { }
		}
		# 必须再调一次无参 WaitForExit:否则 Start-Process -PassThru 拿到的
		# Process 对象 ExitCode 可能仍未被填充(PowerShell 已知行为)
		$i.Proc.WaitForExit()
	}
}

# ---------------------------------------------------------------- 各模式

function Invoke-SingleCase {
	param(
		[string]$Name,
		[hashtable]$EnvVars,
		[int]$FrameCount,
		[string[]]$Expect,
		[int]$TimeoutSec = 180,
		[string]$Note = ''
	)
	Write-Host "[$Name] 启动 $Note" -ForegroundColor Cyan
	$inst = Start-Instance -Name $Name -EnvVars $EnvVars -FrameCount $FrameCount
	Wait-Instances -Instances @($inst) -TimeoutSec $TimeoutSec
	return Test-Instance -Instance $inst -Expect $Expect
}

function Invoke-MpCase {
	param([int]$ClientCount, [int]$FrameCount)
	$ip = Get-LocalIp
	$total = $ClientCount + 1
	Write-Host "[mp] 1 主机 + $ClientCount 客户端 (共 $total 人),主机IP $ip" -ForegroundColor Cyan

	$instances = @()
	# WHITEBOX_HOST=N 是 net.gd 既有的测试钩子:凑够N 名客户端立即开局。
	# 必须等于客户端总数,否则先到的一凑够就开局,后到的会被
	# _on_peer_connected 当"迟到连接"踢掉,客户端还会反复重连。
	$instances += Start-Instance -Name 'mp-host' -FrameCount $FrameCount -EnvVars @{
		WHITEBOX_HOST = "$ClientCount"
		WHITEBOX_NPC  = '4'
	}
	Start-Sleep -Seconds 2   # 等主机把房建起来再让客户端连
	for ($n = 1; $n -le $ClientCount; $n++) {
		$instances += Start-Instance -Name "mp-client$n" -FrameCount $FrameCount -EnvVars @{
			WHITEBOX_JOIN = $ip
		}
		Start-Sleep -Milliseconds 700
	}

	Wait-Instances -Instances $instances -TimeoutSec ([int]($FrameCount / 60) + 180)

	$results = @()
	foreach ($i in $instances) {
		$expect = @("联机开局")
		if ($i.Name -eq 'mp-host') { $expect += "host=true" } else { $expect += "host=false" }
		$results += Test-Instance -Instance $i -Expect $expect
	}
	# 补充断言:座位号必须两两不同,否则种子世界/计分会串
	$seats = @()
	foreach ($i in $instances) {
		$text = Get-Content -LiteralPath $i.Out -Raw -Encoding UTF8
		foreach ($m in [regex]::Matches($text, 'seat=(\d+)/(\d+)')) {
			$seats += [int]$m.Groups[1].Value
		}
	}
	$dup = ($seats | Group-Object | Where-Object Count -gt 1)
	if ($dup) {
		$results += [pscustomobject]@{
			Name = 'mp-seats'; Passed = $false
			Problems = @("座位号重复: $($dup.Name -join ',')")
		}
	}
	else {
		$results += [pscustomobject]@{ Name = 'mp-seats'; Passed = $true; Problems = @() }
	}
	return $results
}

# ---------------------------------------------------------------- 主流程

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$script:godotBin = Find-Godot
Write-Host "Godot : $script:godotBin"
Write-Host "项目  : $ProjectRoot"
Write-Host ""

# 新增/改名的脚本要先导入,否则 class_name 尚未注册,运行时会Parse Error
Write-Host "预导入资源..." -ForegroundColor DarkGray
$imp = Start-Process -FilePath $script:godotBin `
	-ArgumentList '--headless', '--path', $ProjectRoot, '--import' `
	-NoNewWindow -Wait -PassThru
if ($imp.ExitCode -ne 0) { throw "资源导入失败,退出码 $($imp.ExitCode)" }

$singleFrames = if ($Frames -gt 0) { $Frames } elseif ($Full) { $FULL_GUARD_FRAMES } else { $QUICK_FRAMES }
$mpFrames = if ($Frames -gt 0) { $Frames } else { $MP_FRAMES }

$all = @()
if ($Mode -in @('single', 'all')) {
	$envVars = @{ WHITEBOX_NPC = '8' }
	$expect = @('白盒Demo')
	$timeout = 180
	$note = "(快速冒烟 $singleFrames 帧)"
	if ($Full) {
		# 全场模式:让对局自己跑到打烊+宽限结束后退出,断言真的走到了结算
		$envVars['WHITEBOX_QUIT_ON_END'] = '1'
		$expect += @('结算', '对局结束')
		$timeout = $FULL_TIMEOUT_SEC
		$note = '(全场对局:5分钟+30秒宽限,约需5.5 分钟)'
	}
	$all += Invoke-SingleCase -Name 'single' -EnvVars $envVars `
		-FrameCount $singleFrames -Expect $expect -TimeoutSec $timeout -Note $note
}
if ($Mode -in @('tutorial', 'all')) {
	$all += Invoke-SingleCase -Name 'tutorial' -EnvVars @{ WHITEBOX_TUTORIAL = '1' } `
		-FrameCount $QUICK_FRAMES -Expect @('白盒Demo') -Note "(教学关 $QUICK_FRAMES 帧)"
}
if ($Mode -in @('phys', 'all')) {
	# 车斗物理回归:守住"薄商品被挤出车外/穿模掉出地图"。
	# 判定由游戏内断言给出(见 phys_stress.gd),这里只认RESULT=PASS。
	$all += Invoke-SingleCase -Name 'phys' -EnvVars @{ WHITEBOX_PHYSTEST = '1'; WHITEBOX_NPC = '0' } `
		-FrameCount 20000 -Expect @('RESULT=PASS') -TimeoutSec 240 `
		-Note '(车斗物理压力测试:静置/正常推行/激烈对抗三阶段)'
}
if ($Mode -in @('char', 'all')) {
	# 角色技能自检:无头下没人按键,不跑这一项则三个角色技能零覆盖。
	# 判定由游戏内断言给出(见 char_probe.gd),这里只认 RESULT=PASS。
	# 帧数给足:无头无渲染时帧率极高(上千 fps),自检按"游戏内秒数"推进,
	# 帧数给小了会在断言跑完前被 --quit-after 截断(踩过)。
	$all += Invoke-SingleCase -Name 'char' -EnvVars @{ WHITEBOX_CHARTEST = '1'; WHITEBOX_NPC = '0' } `
		-FrameCount 20000 -Expect @('RESULT=PASS') -TimeoutSec 180 `
		-Note '(角色技能自检:三主动 + 三被动)'
}
if ($Mode -in @('mp', 'all')) {
	$all += Invoke-MpCase -ClientCount $Clients -FrameCount $mpFrames
}

Write-Host ""
Write-Host "==================== 结果 ====================" -ForegroundColor White
foreach ($r in $all) {
	if ($r.Passed) {
		Write-Host ("  PASS  {0}" -f $r.Name) -ForegroundColor Green
	}
	else {
		Write-Host ("  FAIL  {0}" -f $r.Name) -ForegroundColor Red
		foreach ($p in $r.Problems) { Write-Host "- $p" -ForegroundColor Red }
	}
}
$failed = @($all | Where-Object { -not $_.Passed })
Write-Host ""
Write-Host ("通过 {0}/{1}   日志目录: {2}" -f ($all.Count - $failed.Count), $all.Count, $OutDir)

if ($failed.Count -gt 0) { exit 1 }
Write-Host "全部通过。" -ForegroundColor Green
exit 0
