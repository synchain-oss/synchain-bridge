<#
.SYNOPSIS
断言所有 Synchain 自有源文件首部含 SPDX 头(B02 gate)。

遍历仓库内 .cpp/.h/.js/.css/.html(排除 web/js/juce/** —— JUCE 官方 helper,
不加 Synchain 版权头,由 REUSE.toml 声明),断言每个文件前 5 行含 "SPDX-License-Identifier"。
用法: pwsh scripts/check-spdx.ps1 [仓库根]
#>
param([string]$Root = (Split-Path $PSScriptRoot -Parent))

$ErrorActionPreference = 'Stop'
$fail = @()

$files = Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object {
    ($_.Extension -in '.cpp', '.h', '.js', '.css', '.html') -and
    ($_.FullName -notmatch '[\\/]web[\\/]js[\\/]juce[\\/]') -and
    ($_.FullName -notmatch '[\\/]build[\\/]')
  }

foreach ($f in $files) {
  $head = Get-Content -LiteralPath $f.FullName -TotalCount 5
  if (-not ($head -match 'SPDX-License-Identifier')) {
    $fail += $f.FullName.Substring($Root.Length + 1)
  }
}

if ($fail.Count -gt 0) {
  Write-Error ("以下源文件首 5 行缺 SPDX 头:" + [Environment]::NewLine + ($fail -join [Environment]::NewLine))
  exit 1
}
Write-Output ("check-spdx 通过: " + $files.Count + " 个源文件全部含 SPDX 头")
exit 0
