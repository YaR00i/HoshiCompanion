# Read only UI Automation geometry for one explicitly selected window.
# Do not request Name, Value, text patterns, screenshots, or invoke controls.
param([Parameter(Mandatory = $true)][long]$TargetHandle,
      [int]$MaxDepth = 12)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HoshiSurfaceDpi {
    [DllImport("user32.dll")]
    public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr value);
}
'@
[void][HoshiSurfaceDpi]::SetThreadDpiAwarenessContext([IntPtr](-4))

function Read-Rect($element) {
    $r = $element.Current.BoundingRectangle
    return @([int][Math]::Round($r.Left), [int][Math]::Round($r.Top),
             [int][Math]::Round($r.Width), [int][Math]::Round($r.Height))
}

$root = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$TargetHandle)
if ($null -eq $root) { throw 'No UI Automation root' }
$rootRect = Read-Rect $root
if ($rootRect[2] -lt 120 -or $rootRect[3] -lt 80) { throw 'Window bounds unavailable' }

$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$queue = New-Object 'System.Collections.Generic.Queue[object]'
$queue.Enqueue([pscustomobject]@{ Element = $root; Depth = 0 })
$items = New-Object 'System.Collections.Generic.List[object]'
$visited = 0
$offscreen = 0
$limit = 240
while ($queue.Count -gt 0 -and $visited -lt $limit) {
    $entry = $queue.Dequeue()
    $element = $entry.Element
    $depth = [int]$entry.Depth
    $visited++
    if ($depth -gt 0) {
        try {
            $current = $element.Current
            if ($current.IsOffscreen) {
                $offscreen++
            } else {
                $r = Read-Rect $element
                $kind = $current.ControlType.ProgrammaticName.Replace('ControlType.', '')
                $items.Add(@{ rect = $r; kind = $kind; depth = $depth })
            }
        } catch [System.Windows.Automation.ElementNotAvailableException] { }
        catch [System.Runtime.InteropServices.COMException] { }
        catch { }
    }
    if ($depth -ge $MaxDepth) { continue }
    try {
        $child = $walker.GetFirstChild($element)
        $siblings = 0
        while ($null -ne $child -and $siblings -lt 80 -and ($queue.Count + $visited) -lt ($limit * 2)) {
            $queue.Enqueue([pscustomobject]@{ Element = $child; Depth = ($depth + 1) })
            $siblings++
            $child = $walker.GetNextSibling($child)
        }
    } catch [System.Windows.Automation.ElementNotAvailableException] { }
    catch [System.Runtime.InteropServices.COMException] { }
    catch { }
}

@{ rect = $rootRect; elements = @($items.ToArray()); visited = $visited;
   offscreen = $offscreen; limited = ($queue.Count -gt 0) } |
    ConvertTo-Json -Compress -Depth 5
