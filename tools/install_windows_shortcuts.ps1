param([switch]$Autostart)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$launcher = Join-Path $projectRoot 'tools\start_hoshi.vbs'
$icon = Join-Path $projectRoot 'assets\hoshi_desktop.ico'
if (-not (Test-Path -LiteralPath $launcher) -or -not (Test-Path -LiteralPath $icon)) {
    throw 'Сначала создайте значок и проверьте tools/start_hoshi.vbs.'
}

$shell = New-Object -ComObject WScript.Shell
$target = Join-Path $env:WINDIR 'System32\wscript.exe'
$arguments = '"' + $launcher + '"'

function New-HoshiShortcut([string]$folder) {
    $path = Join-Path $folder 'Хоши.lnk'
    if (Test-Path -LiteralPath $path) {
        $existing = $shell.CreateShortcut($path)
        if ($existing.TargetPath -ne $target -or $existing.Arguments -ne $arguments) {
            throw "Здесь уже есть другой ярлык: $path"
        }
    }
    $shortcut = $shell.CreateShortcut($path)
    $shortcut.TargetPath = $target
    $shortcut.Arguments = $arguments
    $shortcut.WorkingDirectory = $projectRoot
    $shortcut.IconLocation = "$icon,0"
    $shortcut.Description = 'Хоши — компаньон на рабочем столе'
    $shortcut.Save()
    Write-Output $path
}

New-HoshiShortcut ([Environment]::GetFolderPath('DesktopDirectory'))
if ($Autostart) {
    New-HoshiShortcut ([Environment]::GetFolderPath('Startup'))
}
