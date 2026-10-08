param([string]$ProjectRoot = (Resolve-Path "$PSScriptRoot\..\.."))

function Write-Wave([string]$Path, [double[]]$Notes, [double]$Seconds, [double]$Volume, [bool]$Percussive = $false) {
    $rate = 22050
    $frames = [int]($rate * $Seconds)
    $pcm = New-Object byte[] ($frames * 2)
    $random = [System.Random]::new(177)
    for ($i = 0; $i -lt $frames; $i++) {
        $t = $i / [double]$rate
        $sample = 0.0
        for ($n = 0; $n -lt $Notes.Length; $n++) {
            $pulse = [Math]::Floor($t / 1.5) % $Notes.Length
            $freq = $Notes[([int]$pulse + $n) % $Notes.Length]
            $sample += [Math]::Sin(2.0 * [Math]::PI * $freq * $t + $n * 0.7) / ($n + 1.0)
        }
        if ($Percussive) {
            $sample = ($sample * [Math]::Exp(-8.0 * $t)) + (($random.NextDouble() * 2.0 - 1.0) * [Math]::Exp(-18.0 * $t) * 0.32)
        } else {
            $sample *= 0.55 + 0.45 * [Math]::Sin([Math]::PI * $t / $Seconds)
        }
        $value = [int][Math]::Max(-32767, [Math]::Min(32767, $sample * 32767 * $Volume))
        $pcm[$i * 2] = $value -band 255
        $pcm[$i * 2 + 1] = ($value -shr 8) -band 255
    }
    $stream = [System.IO.File]::Create($Path)
    $writer = [System.IO.BinaryWriter]::new($stream)
    $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
    $writer.Write([int](36 + $pcm.Length))
    $writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
    $writer.Write([int]16); $writer.Write([int16]1); $writer.Write([int16]1)
    $writer.Write([int]$rate); $writer.Write([int]($rate * 2)); $writer.Write([int16]2); $writer.Write([int16]16)
    $writer.Write([Text.Encoding]::ASCII.GetBytes('data')); $writer.Write([int]$pcm.Length); $writer.Write($pcm)
    $writer.Dispose(); $stream.Dispose()
}

$musicDir = Join-Path $ProjectRoot 'assets\audio\music'
$sfxDir = Join-Path $ProjectRoot 'assets\audio\sfx'
[IO.Directory]::CreateDirectory($musicDir) | Out-Null
[IO.Directory]::CreateDirectory($sfxDir) | Out-Null

$tracks = @{
    map = @(110.0, 164.8, 220.0); battle = @(146.8, 220.0, 293.7); elite = @(130.8, 196.0, 261.6)
    boss = @(82.4, 123.5, 164.8); shop = @(196.0, 246.9, 293.7); rest = @(174.6, 220.0, 329.6); breakthrough = @(220.0, 329.6, 440.0)
}
foreach ($name in $tracks.Keys) { Write-Wave (Join-Path $musicDir "$name.wav") $tracks[$name] 12.0 0.14 $false }

$effects = @{
    click = 520.0; cast = 740.0; hit = 150.0; shield = 310.0; qi = 610.0
    relic = 880.0; purchase = 990.0; chest = 430.0; breakthrough = 220.0
    enemy_beast = 105.0; enemy_cultivator = 360.0; enemy_construct = 185.0
}
foreach ($name in $effects.Keys) { Write-Wave (Join-Path $sfxDir "$name.wav") @($effects[$name], $effects[$name] * 1.5) 0.45 0.32 $true }
