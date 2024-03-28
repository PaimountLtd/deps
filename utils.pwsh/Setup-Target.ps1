function Setup-Target {
    if ( ! ( Test-Path function:Log-Output ) ) {
        . $PSScriptRoot/Logger.ps1
    }

    $Target64Bit = ( $script:Target -eq 'x64' )

    $script:ConfigData = @{
        Arch = ('x86', 'x64')[$Target64Bit]
        UnixArch = ('x86', 'x86_64')[$Target64Bit]
        CmakeArch = ('Win32', 'x64')[$Target64Bit]
        Bitness = ('32', '64')[$Target64Bit]
        OutputPath = "${script:ProjectRoot}\windows\obs-${script:PackageName}-${script:Target}"
    }

    Log-Debug "
Architecture    : $($script:ConfigData.Arch)
CMake arch      : $($script:ConfigData.CmakeArch)
Unix arch       : $($script:ConfigData.UnixArch)
Target          : $($script:Target)
Output dir      : $($script:ConfigData.OutputPath)
Working dir     : $($script:WorkRoot)
Project dir     : $($script:ProjectRoot)
"
}

function Setup-BuildParameters {
    if ( ! ( Test-Path function:Log-Output ) ) {
        . $PSScriptRoot/Logger.ps1
    }

    $NumProcessors = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors

    if ( $NumProcessors -gt 1 ) {
        $env:UseMultiToolTask = $true
        $env:EnforceProcessCountAcrossBuilds = $true
    }

    $VisualStudioData = Find-VisualStudio

    $VisualStudioId = "Visual Studio {0} {1}" -f @(
        ([System.Version] $VisualStudioData.Version).Major
        ( $VisualStudioData.Name -split ' ')[3]
    )

    $script:CmakeOptions = @(
        '-A', $script:ConfigData.CmakeArch
        '-G', $VisualStudioId
        "-DCMAKE_INSTALL_PREFIX=$($script:ConfigData.OutputPath)"
        "-DCMAKE_PREFIX_PATH=$($script:ConfigData.OutputPath)"
        "-DCMAKE_IGNORE_PREFIX_PATH=C:\Strawberry\c"
        "-DCMAKE_BUILD_TYPE=${script:Configuration}"
        '--no-warn-unused-cli'
    )

    if ( $script:Quiet ) {
        $script:CmakeOptions += @(
            '-Wno-deprecated', '-Wno-dev', '--log-level=ERROR'
        )
    }

    Log-Debug @"

CMake options   : $($script:CmakeOptions)
Multi-process   : ${NumProcessors}
"@
}

function Find-VisualStudio {
    <#
        .SYNOPSIS
            Finds available Visual Studio instance.
        .DESCRIPTION
            Uses WMI (Windows Management Instrumentation) to find an installed
            Visual Studio instance on the host system.
        .EXAMPLE
            Find-VisualStudio
    #>

    try {
        $VisualStudioData = Get-CimInstance -ClassName MSFT_VSInstance -ErrorAction Stop
        Log-Message "Successfully retrieved Visual Studio instance data."
    } catch {
        Log-Message "Failed to retrieve Visual Studio instance data."
        Log-Message "Error details: $_"
        if ($_.Exception.InnerException) {
            Log-Message "Inner exception details: $($_.Exception.InnerException.Message)"
        }
        # Log additional error properties
        Log-Message "Exception Type: $($_.Exception.GetType().FullName)"
        Log-Message "Error Message: $($_.Exception.Message)"
        Log-Message "Error Category: $($_.CategoryInfo.Category)"
        Log-Message "Error Target: $($_.CategoryInfo.TargetName)"
        Log-Message "Error Target Type: $($_.CategoryInfo.TargetType)"
        # Environmental context
        Log-Message "PowerShell Version: $($PSVersionTable.PSVersion)"
        Log-Message "OS Version: $([Environment]::OSVersion)"
        # Uncomment if needed
        # Log-Message "Loaded Assemblies: $([AppDomain]::CurrentDomain.GetAssemblies() | Out-String)"
    }

    # Prefer VS versions in this order:
    # 1. VS2022 Release (stable)
    # 2. VS2022 Preview
    # 3. VS2019 Release
    [string[]]$SupportedVSVersions =
        "VisualStudio.17.Release",
        "VisualStudio.17.Preview",
        "VisualStudio.16.Release"
    $NumSupportedVSVersions = $SupportedVSVersions.length

    if ( $VisualStudioData.GetType() -eq [object[]] ) {
        for ( $i = 0; $i -lt $NumSupportedVSVersions; $i++ ) {
            $VisualStudioDataTemp = ($VisualStudioData | Where-Object {$_.ChannelId -eq $SupportedVSVersions[$i]} | Sort-Object -Property Version)[0]
            if ( $VisualStudioDataTemp ) {
                break;
            }
        }
        $VisualStudioData = $VisualStudioDataTemp
    }

    if ( ! ( $VisualStudioData ) -or ( $VisualStudioData.Version -lt 16 ) ) {
        $ErrorMessage = @(
            "A Visual Studio installation (2019 or newer) is required for this build script.",
            "The Visual Studio Community edition is available for free at https://visualstudio.microsoft.com/vs/community/.",
            "",
            "If Visual Studio is indeed installed, locate the directory ",
            " 'C:\ProgramData\Microsoft\VisualStudio\Packages\Microsoft.VisualStudio.Setup.WMIProvider,Version=xxxx'",
            " right-click the file 'Microsoft.Visualstudio.Setup.WMIProvider.msi' and choose 'repair'."
        )

        throw $ErrorMessage
    }

    return $VisualStudioData
}
