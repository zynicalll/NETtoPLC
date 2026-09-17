param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\src\NetToPlc.App\Assets\AppIcon.ico')
)

Add-Type -AssemblyName System.Drawing

$outputPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $outputPath
[System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null

function New-RoundedRectanglePath {
    param(
        [float]$X,
        [float]$Y,
        [float]$Width,
        [float]$Height,
        [float]$Radius
    )

    $diameter = $Radius * 2
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $path.AddArc($X, $Y, $diameter, $diameter, 180, 90)
    $path.AddArc($X + $Width - $diameter, $Y, $diameter, $diameter, 270, 90)
    $path.AddArc(
        $X + $Width - $diameter,
        $Y + $Height - $diameter,
        $diameter,
        $diameter,
        0,
        90)
    $path.AddArc($X, $Y + $Height - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-IconPng {
    param([int]$Size)

    $bitmap = [System.Drawing.Bitmap]::new(
        $Size,
        $Size,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.Clear([System.Drawing.Color]::Transparent)

        $margin = [Math]::Max(1.0, $Size * 0.035)
        $radius = [Math]::Max(2.0, $Size * 0.18)
        $backgroundPath = New-RoundedRectanglePath `
            -X $margin `
            -Y $margin `
            -Width ($Size - 2 * $margin) `
            -Height ($Size - 2 * $margin) `
            -Radius $radius
        $backgroundBrush = [System.Drawing.SolidBrush]::new(
            [System.Drawing.Color]::FromArgb(255, 11, 110, 105))
        $borderPen = [System.Drawing.Pen]::new(
            [System.Drawing.Color]::FromArgb(255, 7, 83, 79),
            [Math]::Max(1.0, $Size * 0.025))

        try {
            $graphics.FillPath($backgroundBrush, $backgroundPath)
            $graphics.DrawPath($borderPen, $backgroundPath)
        }
        finally {
            $backgroundBrush.Dispose()
            $borderPen.Dispose()
            $backgroundPath.Dispose()
        }

        $left = $Size * 0.29
        $right = $Size * 0.71
        $top = $Size * 0.27
        $bottom = $Size * 0.73
        $letterPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
        $letterPath.AddLine($left, $bottom, $left, $top)
        $letterPath.AddLine($left, $top, $right, $bottom)
        $letterPath.AddLine($right, $bottom, $right, $top)

        $letterPen = [System.Drawing.Pen]::new(
            [System.Drawing.Color]::White,
            [Math]::Max(1.5, $Size * 0.105))
        $letterPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $letterPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $letterPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round

        try {
            $graphics.DrawPath($letterPen, $letterPath)
        }
        finally {
            $letterPen.Dispose()
            $letterPath.Dispose()
        }

        $stream = [System.IO.MemoryStream]::new()
        $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        return ,$stream.ToArray()
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

$sizes = @(16, 24, 32, 48, 64, 128, 256)
$images = foreach ($size in $sizes) {
    [pscustomobject]@{
        Size = $size
        Data = [byte[]](New-IconPng -Size $size)
    }
}

$stream = [System.IO.File]::Create($outputPath)
$writer = [System.IO.BinaryWriter]::new($stream)

try {
    $writer.Write([uint16]0)
    $writer.Write([uint16]1)
    $writer.Write([uint16]$images.Count)

    $offset = 6 + 16 * $images.Count
    foreach ($image in $images) {
        $dimension = if ($image.Size -eq 256) { 0 } else { $image.Size }
        $writer.Write([byte]$dimension)
        $writer.Write([byte]$dimension)
        $writer.Write([byte]0)
        $writer.Write([byte]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]32)
        $writer.Write([uint32]$image.Data.Length)
        $writer.Write([uint32]$offset)
        $offset += $image.Data.Length
    }

    foreach ($image in $images) {
        $writer.Write([byte[]]$image.Data)
    }
}
finally {
    $writer.Dispose()
    $stream.Dispose()
}

Write-Output "Generated $outputPath"
