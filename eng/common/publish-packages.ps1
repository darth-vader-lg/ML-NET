[CmdletBinding(PositionalBinding=$false)]
Param(
    [string][Alias('c')]$configuration = "Release",
    [string]$platform = $null,
    [string][Alias('k', "api-key")]$apiKey,
    [int][Alias('t')]$timeout = 3601, # Workaround for the timeout; it must not be a multiple of 60, otherwise it will be ignored
    [string][Alias('u')]$url,
    [switch][Alias('n')]$nuget,
    [switch][Alias('g')]$github,
    [switch][Alias('h')] $help,
    [Parameter(ValueFromRemainingArguments=$true)][String[]]$properties
)

function Print-Usage() {
    Write-Host "  -configuration <value>  Build configuration: 'Debug' or 'Release' (short: -c)"
    Write-Host "  -platform <value>       Platform configuration: 'x86', 'x64' or any valid Platform value"
    Write-Host "  -url <value>            The url wher to publish (short: -u)"
    Write-Host "  -nuget                  Publish on the standard NuGet.org index (short: -n)"
    Write-Host "  -github                 Publish on the standard GitHub index (short: -g)"
    Write-Host "  -api-key <value>        The api key with write rights for publishing (short: -k)"
    Write-Host "  -timeout <value>        The timeout for publishing, in seconds (short: -t)"
    Write-Host "  -help                   Print help and exit"
}

try {

    if ($help -or (($null -ne $properties) -and ($properties.Contains('/help') -or $properties.Contains('/?'))) -or (-not $url -and -not $nuget -and -not $github)) {
        Print-Usage
        exit 0
    }

    # Set the scipt root if launched in PowerShell ISE
    if (-not($PSScriptRoot) -and $psISE) { $scriptRoot = Split-Path $psISE.CurrentFile.FullPath } else { $scriptRoot = $PSScriptRoot }

    # Check for the api key consistence
    if (($apiKey -eq "") -and $nuget) {
        if (-not (Test-Path env:NUGET_NUPKG_PUSH_KEY) -or $env:NUGET_NUPKG_PUSH_KEY -eq "") {
            Write-Error "Push api-key not specified!"
            Write-Error "Use the -api-key switch or define the environment variable NUGET_NUPKG_PUSH_KEY"
            Print-Usage
            exit 1
        }
    }
    if (($apiKey -eq "") -and $github) {
        if (-not (Test-Path env:GITHUB_NUPKG_PUSH_KEY) -or $env:GITHUB_NUPKG_PUSH_KEY -eq "") {
            Write-Error "Push api-key not specified!"
            Write-Error "Use the -api-key switch or define the environment variable GITHUB_NUPKG_PUSH_KEY"
            Print-Usage
            exit 1
        }
    }

    # Directory relative to the selected platform
    if ($platform -ne "") {
        $platformDir = $platform, $configuration -join "."
    }
    else {
        $platformDir = $configuration
    }

    # List of packages
    $packages = Get-ChildItem -Path ([IO.Path]::Combine($scriptRoot, "..", "..", "artifacts", "packages", "$platformDir", "Shipping")) -Filter "*.nupkg"

    # List of projects
    $prjNameConvert = @{}
    $prjNameConvert["Microsoft.ML.SamplesUtils"] = "Microsoft.ML.SampleUtils"
    $projects = Get-ChildItem -Path "src" -Directory | ForEach-Object{
        if ($_.Name -in $prjNameConvert.Keys) {
            $prjNameConvert[$_.Name]
        }
        else {
            $_.Name
        }
    }

    # List of projects to exclude
    $exclude = (`
        "Native",`
        "Redist"`
        <#"Microsoft.ML.DnnImageFeaturizer.AlexNet",#>`
        <#"Microsoft.ML.DnnImageFeaturizer.ResNet18",#>`
        <#"Microsoft.ML.DnnImageFeaturizer.ResNet50",#>`
        <#"Microsoft.ML.DnnImageFeaturizer.ResNet101"#>`
    )

    # Publish to url
    if ($url) {
        # Push the packages
        Write-Output "Pushing the packages on $url..."
        foreach ($project in $projects) {
            # Check if the project is excluded
            if ($exclude.Contains($project)) { continue }
            foreach ($package in $packages) {
                if ($package.Name.Contains($project)) {
                    $versionIx = $package.Name.IndexOf($project)
                    if ($versionIx -gt -1) { $versionIx = $versionIx + $project.Length + 1 } else { continue }
                    $val = 0
                    if ([int]::TryParse($package.Name[$versionIx], [ref]$val)) {
                        # Push the package
                        $prms = @($package.FullName, "--force-english-output", "--no-symbols",  "true",  "--timeout", $timeout, "--source", $url)
                        $pathInfo = [System.Uri]$url
                        if ($pathInfo.IsUnc) {
                            $prms = $prms + @("--skip-duplicate")
                            if ($key) { $prms = $prms + @("--api-key", $key) }
                        }
                        elseif (-not(Test-Path -PathType Container -Path $url)) {
                            New-Item -ItemType Directory -Path $url
                        }
                        dotnet nuget push $prms
                        break
                    }
                }
            }
        }
    }

    # Publish on nuget
    if ($nuget) {
        # Push the packages
        Write-Output "Pushing the packages on NuGet..."
        if ($apiKey -eq "") { $key = $env:NUGET_NUPKG_PUSH_KEY } else { $key = $apiKey }
        foreach ($project in $projects) {
            # Check if the project is excluded
            if ($exclude.Contains($project)) { continue }
            foreach ($package in $packages) {
                if ($package.Name.Contains($project)) {
                    $versionIx = $package.Name.IndexOf($project)
                    if ($versionIx -gt -1) { $versionIx = $versionIx + $project.Length + 1 } else { continue }
                    $val = 0
                    if ([int]::TryParse($package.Name[$versionIx], [ref]$val)) {
                        # Push the package
                        dotnet nuget push $package.FullName --force-english-output --skip-duplicate --no-symbols true --timeout $timeout --source "https://api.nuget.org/v3/index.json" --api-key $key
                        break
                    }
                }
            }
        }
    }

    # Publish on GitHub
    if ($github) {
        # GitHub package destination
        $pushOrigin = (((git remote -v) -match "(push)") -split '\t')[0]
        $pushUrl = git remote get-url --push $pushOrigin
        $user = Split-Path -leaf (Split-Path $pushUrl)
        $source = "https://nuget.pkg.github.com/", $user, "/index.json" -join ''
        # Push the packages
        Write-Output "Pushing the packages on GitHub..."
        if ($apiKey -eq "") { $key = $env:GITHUB_NUPKG_PUSH_KEY } else { $key = $apiKey }
        foreach ($project in $projects) {
            # Check if the project is excluded
            if ($exclude.Contains($project)) { continue }
            foreach ($package in $packages) {
                if ($package.Name.Contains($project)) {
                    $versionIx = $package.Name.IndexOf($project)
                    if ($versionIx -gt -1) { $versionIx = $versionIx + $project.Length + 1 } else { continue }
                    $val = 0
                    if ([int]::TryParse($package.Name[$versionIx], [ref]$val)) {
                        # Push the package
                        dotnet nuget push $package.FullName --force-english-output --skip-duplicate --no-symbols true --timeout $timeout --source $source --api-key $key
                        break
                    }
                }
            }
        }
    }

    exit 0
}
catch {
    Write-Host $_.ScriptStackTrace
    exit 1
}
