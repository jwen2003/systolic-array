param(
    [string]$Verilator = "verilator",
    [int]$RandomTests = 100,
    [string]$BuildRoot = "build/regression"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$resolvedBuildRoot = Join-Path $repoRoot $BuildRoot

$rtl = @(
    "rtl/systolic_pe.sv",
    "rtl/systolic_array.sv",
    "rtl/input_feeder.sv",
    "rtl/systolic_controller.sv",
    "rtl/systolic_array_top.sv"
)

$tests = @(
    @{ Name = "pe";         Top = "tb_systolic_pe";           Tb = "tb/tb_systolic_pe.sv" },
    @{ Name = "array";      Top = "tb_systolic_array";        Tb = "tb/tb_systolic_array.sv" },
    @{ Name = "feeder";     Top = "tb_input_feeder";          Tb = "tb/tb_input_feeder.sv" },
    @{ Name = "controller"; Top = "tb_systolic_controller";   Tb = "tb/tb_systolic_controller.sv" },
    @{ Name = "top";        Top = "tb_systolic_array_top";    Tb = "tb/tb_systolic_array_top.sv" },
    @{ Name = "random_n1_k1"; Top = "tb_systolic_array_random"; Tb = "tb/tb_systolic_array_random.sv"; Params = @("-GN=1", "-GK=1") },
    @{ Name = "random_n2_k1"; Top = "tb_systolic_array_random"; Tb = "tb/tb_systolic_array_random.sv"; Params = @("-GN=2", "-GK=1") },
    @{ Name = "random_n2_k2"; Top = "tb_systolic_array_random"; Tb = "tb/tb_systolic_array_random.sv"; Params = @("-GN=2", "-GK=2") },
    @{ Name = "random_n2_k3"; Top = "tb_systolic_array_random"; Tb = "tb/tb_systolic_array_random.sv"; Params = @("-GN=2", "-GK=3") },
    @{ Name = "random_n4_k1"; Top = "tb_systolic_array_random"; Tb = "tb/tb_systolic_array_random.sv"; Params = @("-GN=4", "-GK=1") },
    @{ Name = "random_n4_k4"; Top = "tb_systolic_array_random"; Tb = "tb/tb_systolic_array_random.sv"; Params = @("-GN=4", "-GK=4") }
)

New-Item -ItemType Directory -Force $resolvedBuildRoot | Out-Null
Push-Location $repoRoot
try {
    foreach ($test in $tests) {
        $buildDir = Join-Path $resolvedBuildRoot $test.Name
        $prefix = "V$($test.Name)"
        $arguments = @(
            "--binary", "--timing", "--Wall",
            "--top-module", $test.Top,
            "--prefix", $prefix,
            "--Mdir", $buildDir
        )
        $arguments += $rtl
        $arguments += $test.Tb
        if ($test.ContainsKey("Params")) {
            $arguments += $test.Params
            $arguments += "-GNUM_RANDOM_TESTS=$RandomTests"
        }

        Write-Host "[BUILD] $($test.Name)"
        & $Verilator @arguments
        if ($LASTEXITCODE -ne 0) { throw "Verilator failed for $($test.Name)" }

        $executable = Join-Path $buildDir "$prefix.exe"
        if (-not (Test-Path $executable)) {
            $executable = Join-Path $buildDir $prefix
        }
        Write-Host "[RUN]   $($test.Name)"
        & $executable
        if ($LASTEXITCODE -ne 0) { throw "Simulation failed for $($test.Name)" }
    }
}
finally {
    Pop-Location
}

Write-Host "Regression passed: 5 directed testbenches and 6 parameter configurations."
