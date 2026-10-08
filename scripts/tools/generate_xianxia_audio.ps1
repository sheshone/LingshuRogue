param([string]$ProjectRoot = (Resolve-Path "$PSScriptRoot\..\.."))

function Write-PcmWave([string]$Path, [int16[]]$Samples, [int]$Rate = 22050) {
    $pcm = New-Object byte[] ($Samples.Length * 2)
    for ($i = 0; $i -lt $Samples.Length; $i++) {
        $pcm[$i * 2] = $Samples[$i] -band 255
        $pcm[$i * 2 + 1] = ($Samples[$i] -shr 8) -band 255
    }
    $stream = [IO.File]::Create($Path)
    $writer = [IO.BinaryWriter]::new($stream)
    $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $writer.Write([int](36 + $pcm.Length))
    $writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt ')); $writer.Write([int]16)
    $writer.Write([int16]1); $writer.Write([int16]1); $writer.Write($Rate); $writer.Write([int]($Rate * 2))
    $writer.Write([int16]2); $writer.Write([int16]16); $writer.Write([Text.Encoding]::ASCII.GetBytes('data'))
    $writer.Write([int]$pcm.Length); $writer.Write($pcm); $writer.Dispose(); $stream.Dispose()
}

function Write-XianxiaMusic([string]$Path, [double]$Root, [double]$Tempo, [int]$Seed) {
    $rate = 22050; $duration = 72.0; $frames = [int]($rate * $duration)
    $samples = New-Object int16[] $frames; $random = [Random]::new($Seed)
    $scale = @(1.0, 1.125, 1.333333, 1.5, 1.777778, 2.0)
    $melody = @(0,2,4,3,1,2,0,5,4,2,3,1,0,2,4,5)
    $wind = 0.0
    for ($i = 0; $i -lt $frames; $i++) {
        $t = $i / [double]$rate; $step = [int][Math]::Floor($t / $Tempo); $local = $t % $Tempo
        $freq = $Root * $scale[$melody[$step % $melody.Length]]
        $pluckEnv = [Math]::Exp(-3.8 * $local)
        $pluck = ([Math]::Sin(2*[Math]::PI*$freq*$t) + .38*[Math]::Sin(2*[Math]::PI*$freq*2.01*$t) + .18*[Math]::Sin(2*[Math]::PI*$freq*3.98*$t)) * $pluckEnv
        $nextFreq = $Root * 2.0 * $scale[$melody[($step + 3) % $melody.Length]]
        $barLocal = $t % ($Tempo * 8.0)
        # Guqin fanyin-inspired high harmonics arrive only at phrase boundaries.
        $bell = ([Math]::Sin(2*[Math]::PI*$Root*3.0*$t) + .28*[Math]::Sin(2*[Math]::PI*$Root*4.5*$t)) * [Math]::Exp(-2.25*$barLocal)
        $fade = [Math]::Min(1.0, [Math]::Min($t/1.2, ($duration-$t)/1.2))
        # Sparse guqin-like plucks and a restrained high chime.  No sustained
        # flute, wind or low drone: those were responsible for the eerie tone.
        $answerLocal = ($t + $Tempo*.5) % ($Tempo*2.0)
        $answer = ([Math]::Sin(2*[Math]::PI*$nextFreq*$t)+.22*[Math]::Sin(2*[Math]::PI*$nextFreq*2.02*$t))*[Math]::Exp(-4.8*$answerLocal)
        $value = ($pluck*.27 + $answer*.13 + $bell*.052) * $fade
        $samples[$i] = [int16][Math]::Max(-32767,[Math]::Min(32767,$value*32767))
    }
    Write-PcmWave $Path $samples $rate
}

function Write-ElementSound([string]$Path, [string]$Element, [int]$Seed) {
    $rate=22050; $duration=0.9; $frames=[int]($rate*$duration); $samples=New-Object int16[] $frames
    $random=[Random]::new($Seed); $smooth=0.0
    for($i=0;$i -lt $frames;$i++){
        $t=$i/[double]$rate; $noise=$random.NextDouble()*2.0-1.0; $smooth=$smooth*.94+$noise*.06
        $fade=[Math]::Sin([Math]::PI*[Math]::Min(1.0,$t/$duration)); $sample=0.0
        switch($Element){
            'metal' { $sample=([Math]::Sin(2*[Math]::PI*(720+480*$t)*$t)*[Math]::Exp(-5*$t)+$smooth*.22)*$fade }
            'wood'  { $sample=($smooth*.44+[Math]::Sin(2*[Math]::PI*330*$t)*.24+[Math]::Sin(2*[Math]::PI*495*$t)*.12)*$fade }
            'water' { $sample=($smooth*.52+[Math]::Sin(2*[Math]::PI*(210+90*[Math]::Sin(8*$t))*$t)*.25)*$fade }
            'fire'  { $crackle=($random.NextDouble()*2-1)*[Math]::Exp(-2.8*$t); $sample=($smooth*.34+$crackle*.34+[Math]::Sin(2*[Math]::PI*(150+240*$t)*$t)*.24)*$fade }
            'earth' { $sample=([Math]::Sin(2*[Math]::PI*(92-18*$t)*$t)*.58+$smooth*.34)*[Math]::Exp(-2.0*$t) }
            default { $sample=($smooth*.28+[Math]::Sin(2*[Math]::PI*(280+160*$t)*$t)*.3)*$fade }
        }
        $samples[$i]=[int16][Math]::Max(-32767,[Math]::Min(32767,$sample*17000))
    }
    Write-PcmWave $Path $samples $rate
}

function Write-UiSound([string]$Path, [double]$Base, [double]$Duration, [int]$Seed) {
    $rate=22050; $frames=[int]($rate*$Duration); $samples=New-Object int16[] $frames; $random=[Random]::new($Seed); $smooth=0.0
    for($i=0;$i -lt $frames;$i++){
        $t=$i/[double]$rate; $noise=$random.NextDouble()*2-1; $smooth=$smooth*.9+$noise*.1
        $env=[Math]::Pow([Math]::Max(0,1-$t/$Duration),2.4)
        $knock=[Math]::Sin(2*[Math]::PI*$Base*$t)*.30+[Math]::Sin(2*[Math]::PI*$Base*.51*$t)*.18
        $sample=($knock+$smooth*.22)*$env
        $samples[$i]=[int16][Math]::Max(-32767,[Math]::Min(32767,$sample*14500))
    }
    Write-PcmWave $Path $samples $rate
}

function Write-JourneySound([string]$Path) {
    $rate=22050; $duration=3.4; $frames=[int]($rate*$duration); $samples=New-Object int16[] $frames
    $notes=@(220.0,293.66,329.63,440.0,493.88,659.25)
    for($i=0;$i -lt $frames;$i++){
        $t=$i/[double]$rate; $sample=0.0
        for($n=0;$n -lt $notes.Length;$n++){
            $start=$n*.34; $local=$t-$start
            if($local -ge 0){
                $env=[Math]::Exp(-1.75*$local)*(1-[Math]::Exp(-22*$local))
                $freq=$notes[$n]
                $sample += ([Math]::Sin(2*[Math]::PI*$freq*$t)+.22*[Math]::Sin(2*[Math]::PI*$freq*2.01*$t))*$env*.18
            }
        }
        $finalLocal=$t-1.85
        if($finalLocal -ge 0){
            $sample += ([Math]::Sin(2*[Math]::PI*880*$t)+.3*[Math]::Sin(2*[Math]::PI*1320*$t))*[Math]::Exp(-1.55*$finalLocal)*.12
        }
        $fade=[Math]::Min(1.0,[Math]::Min($t/.08,($duration-$t)/.35))
        $samples[$i]=[int16][Math]::Max(-32767,[Math]::Min(32767,$sample*$fade*19000))
    }
    Write-PcmWave $Path $samples $rate
}

function Write-EnemySound([string]$Path, [string]$Family, [double]$Base, [int]$Seed) {
    $rate=22050; $duration=.82; $frames=[int]($rate*$duration); $samples=New-Object int16[] $frames
    $random=[Random]::new($Seed); $smooth=0.0
    for($i=0;$i -lt $frames;$i++){
        $t=$i/[double]$rate; $noise=$random.NextDouble()*2.0-1.0; $smooth=$smooth*.92+$noise*.08; $sample=0.0
        if($Family -eq 'beast'){
            $env=[Math]::Sin([Math]::PI*$t/$duration)*[Math]::Exp(-.65*$t)
            $sweep=$Base*(1.0-.32*$t/$duration)
            $sample=([Math]::Sin(2*[Math]::PI*$sweep*$t+.8*[Math]::Sin(2*[Math]::PI*23*$t))*.48+$smooth*.7)*$env
        } elseif($Family -eq 'construct'){
            foreach($hit in @(0.03,.19,.36)) { $d=$t-$hit; if($d -ge 0 -and $d -lt .16){ $sample += ($smooth*.85+[Math]::Sin(2*[Math]::PI*$Base*(1+3*$d)*$t)*.4)*[Math]::Exp(-24*$d) } }
        } else {
            $env=[Math]::Sin([Math]::PI*[Math]::Min(1.0,$t/.48))*[Math]::Exp(-1.8*$t)
            $whoosh=$smooth*[Math]::Sin([Math]::PI*$t/$duration)
            $metal=[Math]::Sin(2*[Math]::PI*($Base+520*$t)*$t)*[Math]::Exp(-5*$t)
            $sample=($whoosh*.72+$metal*.28)*$env
        }
        $samples[$i]=[int16][Math]::Max(-32767,[Math]::Min(32767,$sample*19000))
    }
    Write-PcmWave $Path $samples $rate
}

$musicDir=Join-Path $ProjectRoot 'assets\audio\music'; $sfxDir=Join-Path $ProjectRoot 'assets\audio\sfx'
$tracks=@{
    map=@(110.0,1.75,11); battle=@(123.47,1.20,13); elite=@(110.0,1.02,17); boss=@(82.41,.86,19)
    shop=@(146.83,1.55,23); rest=@(130.81,1.92,29); breakthrough=@(164.81,1.38,31)
}
foreach($name in $tracks.Keys){$p=$tracks[$name]; Write-XianxiaMusic (Join-Path $musicDir "$name.wav") $p[0] $p[1] $p[2]}

$enemies=@{
 training_puppet=@('construct',178,101); bandit=@('cultivator',245,103); steel_fang_wolf=@('beast',82,107)
 fire_tail_wolf=@('beast',96,109); rock_shell_tortoise=@('beast',61,113); withered_vine_spirit=@('beast',72,127)
 ember_dust_moth=@('beast',132,131); dusk_beak_crow=@('beast',155,137); iron_bark_guardian=@('construct',142,139)
 blood_root_demon=@('beast',67,149); seal_bearing_enforcer=@('cultivator',278,151); black_tide_chief=@('cultivator',196,157)
}
foreach($id in $enemies.Keys){$p=$enemies[$id]; Write-EnemySound (Join-Path $sfxDir "enemy_$id.wav") $p[0] $p[1] $p[2]}
foreach($element in @('metal','wood','water','fire','earth','neutral')){ Write-ElementSound (Join-Path $sfxDir "cast_$element.wav") $element (211 + $element.Length) }
$ui=@{click=128;hover=220;node=108;card=148;choice=118;reward=196;shop=98;inventory=136;confirm=168;back=88}
foreach($name in $ui.Keys){ Write-UiSound (Join-Path $sfxDir "$name.wav") $ui[$name] (.16 + (($name.Length % 3)*.035)) (301+$name.Length) }
Write-JourneySound (Join-Path $sfxDir 'journey.wav')
