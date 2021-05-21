[CmdletBinding(PositionalBinding=$false)]
Param(
  [string][Alias('c')]$configuration = "Release",
  [Parameter(ParameterSetName="api-key")][string][Alias('k')]$apiKey,
  [string]$platform = $null,
  [Parameter(ValueFromRemainingArguments=$true)][String[]]$properties
)

# Check for the api key consistence
if (($apiKey -eq "") -and (-not (Test-Path env:GITHUB_NUPKG_PUSH_KEY) -or $env:GITHUB_NUPKG_PUSH_KEY -eq "")) {
    Write-Error "Push apy-key not specified!"
    Write-Error "Use the -api-key switch or define the environment variable GITHUB_NUPKG_PUSH_KEY"
    exit 1
}
if ($apiKey -eq "") {
    $apiKey = $env:GITHUB_NUPKG_PUSH_KEY
}

# List of projects to exclude
$exclude = (`
    "Microsoft.ML.DnnImageFeaturizer.AlexNet",`
    "Microsoft.ML.DnnImageFeaturizer.ResNet18",`
    "Microsoft.ML.DnnImageFeaturizer.ResNet50",`
    "Microsoft.ML.DnnImageFeaturizer.ResNet101"`
)

# List of created packages in the selected configuration and platform
if ($platform -ne "") {
    $platformDir = $platform, $configuration -join "."
}
else {
    $platformDir = $configuration
}

# List of projects and packages
$projects = Get-ChildItem -Path "src" -Directory
$packages = Get-ChildItem -Path ("artifacts", "packages", $platformDir, "Shipping" -join "\") -Filter "*.nupkg"

# Push the packages
Write-Output "Pushing the packages on GitHub..."
foreach ($project in $projects) {
    # Check if the project is excluded
    if ($exclude.Contains($project.Name)) { continue }
    foreach ($package in $packages) {
        if ($package.Name.Contains($project.Name)) {
            $version = $package.Name.Replace(($project.Name, "." -join ''), "")
            $val = 0
            if ([int]::TryParse($version[0], [ref]$val)) {
                $version = $version.Replace(".nupkg", "")
                # Push the package
                dotnet nuget push $package.FullName --force-english-output --skip-duplicate --no-symbols true --timeout 600 --source "https://nuget.pkg.github.com/dart-vader-lg/index.json" --api-key $apiKey
                break
            }
        }
    }
}
