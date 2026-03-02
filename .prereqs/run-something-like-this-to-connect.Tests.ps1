Describe "Initial storage UNC tests" -Skip {
    # IMPORTANT:  Make sure one or the other of these is skipped, 
    # until I get around to putting them together gracefully, 
    # or I might end up with UNC conflicts due to parallelism.
    # TODO.
    Describe "Basic file share operations work by UNC" -Skip {
        BeforeAll {
            $tfstate_file = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, 'AA-tf', 'terraform.tfstate'))
            $gallery_path = (jq -r '.resources[] | select(.type=="github_actions_variable") | .instances[] | select(.attributes.variable_name=="THE_STORACCT_SHAREPATH") | .attributes.value' $tfstate_file) # UNC of format "\\fqdn\subfolder"
            $storage_account_name = (jq -r '.resources[] | select(.type=="github_actions_variable") | .instances[] | select(.attributes.variable_name=="THE_STORACCT_NAME") | .attributes.value' $tfstate_file)
            $storage_account_key = az storage account keys list `
                --subscription "$([Environment]::GetEnvironmentVariable('DEMOS_my_azure_subscription_id', 'User'))" `
                --resource-group "$([Environment]::GetEnvironmentVariable('DEMOS_my_workload_nickname', 'User'))-rg-demo" `
                --account-name $storage_account_name `
                --query '[0].value' `
                --output 'tsv'
            $storage_share_name = (jq -r '.resources[] | select(.type=="github_actions_variable") | .instances[] | select(.attributes.variable_name=="THE_SHARE_NAME") | .attributes.value' $tfstate_file)
            Write-Host("Gallery path is:  $gallery_path")
            $net_use_server = ($gallery_path -split '\\' | Where-Object { $_ -ne '' })[0]
            $existing_net_use_line = net use | Where-Object { $_ -match [regex]::Escape($gallery_path) } | Select-Object -First 1
            if ($existing_net_use_line -and $existing_net_use_line -match '([A-Z]):') {
                $net_use_drive_letter = $Matches[1] + ':'
                Write-Host("Reusing existing net use drive letter: $net_use_drive_letter")
            }
            else {
                # Use cmdkey to install the credential before net use (no /user: inline).
                # This prevents error 1219 caused by competing OAuth/HTTPS sessions that
                # AZ CLI may have left on the same hostname.
                cmdkey /delete:$net_use_server 2>$null | Out-Null
                cmdkey /add:$net_use_server /user:"Azure\$storage_account_name" /pass:$storage_account_key | Out-Null
                $net_use_output = net use * "$gallery_path"
                $net_use_drive_letter = ($net_use_output | Where-Object { $_ -match '([A-Z]):' } | Select-Object -First 1) -replace '^.*?([A-Z]:).*$', '$1'
                Write-Host("Drive letter is:  $net_use_drive_letter")
            }
        }
        It "should be reachable as a UNC path" {
            Test-Path $gallery_path | Should -BeTrue
        }
        It "should allow listing contents via UNC" {
            { Get-ChildItem $gallery_path } | Should -Not -Throw
        }
        It "should allow creating and deleting a file via UNC" {
            $testFile = Join-Path $gallery_path 'testfile.txt'
            Set-Content -Path $testFile -Value 'test' -Force
            Test-Path $testFile | Should -BeTrue
            Remove-Item $testFile -Force
            Test-Path $testFile | Should -BeFalse
        }
        Describe "PowerShell should work via UNC too" {
            BeforeAll {
                $ps_gallery_nickname = 'TfTestGallery'
                Write-Host("Before registering a new repository, there are $((Get-PSRepository).Length) repositories")
                Register-PSRepository `
                    -Name $ps_gallery_nickname `
                    -SourceLocation $gallery_path `
                    -PublishLocation $gallery_path `
                    -InstallationPolicy 'Trusted'
                Write-Host("After registering a new repository, there are now $((Get-PSRepository).Length) repositories")
            }
            It "should not be able to find a fake module" {
                $all_xyzzy_modules = Find-Module `
                    -Name 'NotARealModule' `
                    -Repository $ps_gallery_nickname `
                    -ErrorAction 'SilentlyContinue' `
                | Select-Object `
                    -Property 'Version' `
                    -ExpandProperty 'Version' 
                $all_xyzzy_modules.Length | Should -Be 0
            }
            It "should not yet have any modules in fact because I have not yet published any" {
                $all_xyzzy_modules = Find-Module `
                    -Repository $ps_gallery_nickname
                $all_xyzzy_modules.Length | Should -Be 0
            }
            AfterAll {
                try {
                    Unregister-PSRepository `
                        -Name $ps_gallery_nickname `
                        -ErrorAction 'SilentlyContinue'
                }
                catch {}
                Write-Host("After unregistering the new repository, there are $((Get-PSRepository).Length) repositories")

            }
        }
        Describe "REST upload via az storage file upload-batch is visible over UNC" {
            BeforeAll {
                $az_upload_test_subfolder = 'az-upload-test'
                $az_upload_test_filename = "az-rest-upload-$(Get-Date -Format 'yyyyMMddHHmmss').txt"
                $az_upload_local_dir = Join-Path $env:TEMP 'az-upload-test-source'
                New-Item -ItemType Directory -Force -Path $az_upload_local_dir | Out-Null
                $az_upload_local_file = Join-Path $az_upload_local_dir $az_upload_test_filename
                Set-Content -Path $az_upload_local_file -Value "Uploaded via az storage file upload-batch at $(Get-Date -Format 'o')" -Force
                az storage file upload-batch `
                    --subscription "$([Environment]::GetEnvironmentVariable('DEMOS_my_azure_subscription_id', 'User'))" `
                    --account-name $storage_account_name `
                    --destination $storage_share_name `
                    --destination-path $az_upload_test_subfolder `
                    --source $az_upload_local_dir `
                    --backup-intent `
                    --auth-mode 'login'
                Write-Host("REST upload complete; expecting file at UNC subfolder '$az_upload_test_subfolder/$az_upload_test_filename'")
            }
            It "should see the REST-uploaded file via UNC path" {
                $expected_unc_path = Join-Path $gallery_path $az_upload_test_subfolder $az_upload_test_filename
                Write-Host("Checking UNC path: $expected_unc_path")
                Test-Path $expected_unc_path | Should -BeTrue
            }
            It "should be able to read back the REST-uploaded file contents via UNC" {
                $expected_unc_path = Join-Path $gallery_path $az_upload_test_subfolder $az_upload_test_filename
                $content = Get-Content $expected_unc_path -Raw
                $content | Should -Match 'Uploaded via az storage file upload-batch'
            }
            AfterAll {
                # Clean up the test subfolder via UNC
                $az_upload_test_unc_subfolder = Join-Path $gallery_path $az_upload_test_subfolder
                if (Test-Path $az_upload_test_unc_subfolder) {
                    Remove-Item -Path $az_upload_test_unc_subfolder -Recurse -Force
                    Write-Host("Removed UNC subfolder: $az_upload_test_unc_subfolder")
                }
                # Clean up local temp source dir
                if (Test-Path $az_upload_local_dir) {
                    Remove-Item -Path $az_upload_local_dir -Recurse -Force
                }
                $az_upload_test_subfolder = $null
                $az_upload_test_filename = $null
                $az_upload_local_dir = $null
                $az_upload_local_file = $null
                Write-Host("Finished az upload test cleanup")
            }
        }
        Describe "Can build a real PowerShell module and install it from the Azure Files share via UNC" {
            BeforeAll {
                $module_build_version = "$(Get-Date -Format 'yyyy').$(Get-Date -Format 'MMdd').$(Get-Date -Format 'HHmm')"
                $module_name = 'HelloWorld'
                $module_source_psd1 = [System.IO.Path]::GetFullPath(
                    [System.IO.Path]::Combine($PSScriptRoot, '..', '..', 'powershell-module-01-tiny', 'src', 'all_my_modules', 'HelloWorld', 'HelloWorld.psd1')
                )
                $module_build_output_dir = Join-Path $env:TEMP 'ps-module-build-output'
                $module_local_gallery_dir = Join-Path $env:TEMP 'ps-module-local-gallery'
                $module_share_subfolder = 'ps-modules-gallery'
                $module_local_gallery_nickname = 'LocalTempGallery'
                $module_unc_gallery_nickname = 'UncTempGallery'
                $module_unc_gallery_path = Join-Path $gallery_path $module_share_subfolder

                # Ensure ModuleBuilder is installed
                if (-not (Get-Module -Name 'ModuleBuilder' -ListAvailable)) {
                    Write-Host("Installing ModuleBuilder from PSGallery ...")
                    Install-Module -Name 'ModuleBuilder' -Repository 'PSGallery' -Scope 'CurrentUser' -Force
                }

                # Fresh build output and local gallery dirs
                if (Test-Path $module_build_output_dir) { Remove-Item $module_build_output_dir -Recurse -Force }
                if (Test-Path $module_local_gallery_dir) { Remove-Item $module_local_gallery_dir -Recurse -Force }
                New-Item -ItemType Directory -Force -Path $module_build_output_dir | Out-Null
                New-Item -ItemType Directory -Force -Path $module_local_gallery_dir | Out-Null

                # Build the module into a versioned output folder
                Write-Host("Building $module_name v$module_build_version from: $module_source_psd1")
                Build-Module `
                    -SourcePath $module_source_psd1 `
                    -OutputDirectory $module_build_output_dir `
                    -VersionedOutputDirectory `
                    -Version $module_build_version
                $built_module_dir = (Get-ChildItem -Path (Join-Path $module_build_output_dir $module_name) -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
                Write-Host("Built module directory: $built_module_dir")

                # Register LocalTempGallery, publish the built module into it, then unregister
                try { Unregister-PSRepository -Name $module_local_gallery_nickname -ErrorAction SilentlyContinue } catch {}
                Register-PSRepository `
                    -Name $module_local_gallery_nickname `
                    -SourceLocation $module_local_gallery_dir `
                    -PublishLocation $module_local_gallery_dir `
                    -InstallationPolicy 'Trusted'
                Write-Host("Registered $module_local_gallery_nickname at $module_local_gallery_dir; publishing ...")
                Publish-Module `
                    -Path $built_module_dir `
                    -Repository $module_local_gallery_nickname `
                    -NuGetApiKey 'ignored' `
                    -Force
                Write-Host("Published to $module_local_gallery_nickname; nupkg files: $(Get-ChildItem $module_local_gallery_dir -Filter '*.nupkg' | Select-Object -ExpandProperty Name)")
                try { Unregister-PSRepository -Name $module_local_gallery_nickname -ErrorAction SilentlyContinue } catch {}
                Write-Host("Unregistered $module_local_gallery_nickname")

                # Upload nupkg files to the Azure Files share under a dedicated subfolder
                # Pre-create the subfolder via UNC (SMB) so Windows' directory cache knows
                # about it before we populate it via REST; otherwise Install-Module gets
                # DirectoryNotFoundException even though the REST upload succeeded.
                New-Item -ItemType Directory -Force -Path $module_unc_gallery_path | Out-Null
                Write-Host("Pre-created UNC gallery subfolder: $module_unc_gallery_path")
                Write-Host("Uploading nupkg files to share '$storage_share_name' under path '$module_share_subfolder' ...")
                az storage file upload-batch `
                    --subscription "$([Environment]::GetEnvironmentVariable('DEMOS_my_azure_subscription_id', 'User'))" `
                    --account-name $storage_account_name `
                    --destination $storage_share_name `
                    --destination-path $module_share_subfolder `
                    --source $module_local_gallery_dir `
                    --backup-intent `
                    --auth-mode 'login'
                Write-Host("Upload complete. UNC gallery path will be: $module_unc_gallery_path")
                # Uninstall any pre-existing copy of the module so later tests start clean
                Remove-Module -Name $module_name -Force -ErrorAction SilentlyContinue
                if (Get-Module -Name $module_name -ListAvailable) {
                    Uninstall-Module -Name $module_name -AllVersions -Force -ErrorAction SilentlyContinue
                }
                Write-Host("Ensured $module_name is not installed before UNC tests begin")
            }
            It "should not have $module_name module available before registering UncTempGallery" {
                Get-Module -Name $module_name -ListAvailable | Should -BeNullOrEmpty
            }
            It "should not have Get-Greeting command available before install" {
                Get-Command 'Get-Greeting' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            }
            Describe "After registering UncTempGallery and installing the module" {
                BeforeAll {
                    try { Unregister-PSRepository -Name $module_unc_gallery_nickname -ErrorAction SilentlyContinue } catch {}
                    Register-PSRepository `
                        -Name $module_unc_gallery_nickname `
                        -SourceLocation $module_unc_gallery_path `
                        -PublishLocation $module_unc_gallery_path `
                        -InstallationPolicy 'Trusted'
                    Write-Host("Registered $module_unc_gallery_nickname at: $module_unc_gallery_path")
                    Install-Module `
                        -Name $module_name `
                        -Repository $module_unc_gallery_nickname `
                        -Force `
                        -Scope 'CurrentUser' `
                        -SkipPublisherCheck
                    Import-Module $module_name -Force
                    Write-Host("Installed and imported $module_name from $module_unc_gallery_nickname")
                }
                It "should find $module_name in UncTempGallery with the expected version" {
                    $found = Find-Module -Name $module_name -Repository $module_unc_gallery_nickname
                    $found | Should -Not -BeNullOrEmpty
                    # Cast to [System.Version] for comparison since it normalises leading zeros (e.g. "0226" -> 226)
                    $found.Version | Should -Be ([System.Version]$module_build_version)
                }
                It "should have Get-Greeting command available after installing from UncTempGallery" {
                    Get-Command 'Get-Greeting' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
                }
                It "should run Get-Greeting without throwing" {
                    { Get-Greeting } | Should -Not -Throw
                }
                AfterAll {
                    try { Unregister-PSRepository -Name $module_unc_gallery_nickname -ErrorAction SilentlyContinue } catch {}
                    Write-Host("Unregistered $module_unc_gallery_nickname")
                }
            }
            AfterAll {
                # Uninstall the module and verify functions are gone
                Remove-Module -Name $module_name -Force -ErrorAction SilentlyContinue
                if (Get-Module -Name $module_name -ListAvailable) {
                    Uninstall-Module -Name $module_name -AllVersions -Force -ErrorAction SilentlyContinue
                }
                Write-Host("Uninstalled $module_name")
                if (Get-Command 'Get-Greeting' -ErrorAction SilentlyContinue) {
                    Write-Warning("Get-Greeting still present after uninstall!")
                }
                else {
                    Write-Host("Confirmed: Get-Greeting command is gone")
                }
                # Remove the share gallery subfolder via UNC
                if (Test-Path $module_unc_gallery_path) {
                    Remove-Item -Path $module_unc_gallery_path -Recurse -Force
                    Write-Host("Removed UNC gallery subfolder: $module_unc_gallery_path")
                }
                # Clean up local temp dirs
                if (Test-Path $module_build_output_dir) { Remove-Item $module_build_output_dir -Recurse -Force }
                if (Test-Path $module_local_gallery_dir) { Remove-Item $module_local_gallery_dir -Recurse -Force }
                $module_build_version = $null
                $module_name = $null
                $module_source_psd1 = $null
                $module_build_output_dir = $null
                $module_local_gallery_dir = $null
                $module_share_subfolder = $null
                $module_local_gallery_nickname = $null
                $module_unc_gallery_nickname = $null
                $module_unc_gallery_path = $null
                Write-Host("Finished module build/publish/install test cleanup")
            }
        }
        AfterAll {
            if ($net_use_drive_letter) {
                net use $net_use_drive_letter /delete
            }
            if ($net_use_server) {
                cmdkey /delete:$net_use_server 2>$null | Out-Null
            }
            $net_use_drive_letter = $null
            $net_use_server = $null
            $net_use_output = $null
            $tfstate_file = $null
            $gallery_path = $null
            $storage_account_key = $null
            $storage_account_name = $null
            $storage_share_name = $null
            Write-Host("Finished cleanup")
        }
    }

    Describe "I can, via UNC, see at least 1 version of my PowerShell module" {
        BeforeAll {
            $tfstate_file = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, 'AA-tf', 'terraform.tfstate'))
            $gallery_path = (jq -r '.resources[] | select(.type=="github_actions_variable") | .instances[] | select(.attributes.variable_name=="THE_STORACCT_SHAREPATH") | .attributes.value' $tfstate_file)
            $storage_account_name = (jq -r '.resources[] | select(.type=="github_actions_variable") | .instances[] | select(.attributes.variable_name=="THE_STORACCT_NAME") | .attributes.value' $tfstate_file)
            $storage_account_key = az storage account keys list `
                --subscription "$([Environment]::GetEnvironmentVariable('DEMOS_my_azure_subscription_id', 'User'))" `
                --resource-group "$([Environment]::GetEnvironmentVariable('DEMOS_my_workload_nickname', 'User'))-rg-demo" `
                --account-name $storage_account_name `
                --query '[0].value' `
                --output 'tsv'
            $net_use_server = ($gallery_path -split '\\' | Where-Object { $_ -ne '' })[0]
            $existing_net_use_line = net use | Where-Object { $_ -match [regex]::Escape($gallery_path) } | Select-Object -First 1
            if ($existing_net_use_line -and $existing_net_use_line -match '([A-Z]):') {
                $net_use_drive_letter = $Matches[1] + ':'
                Write-Host("Reusing existing net use drive letter: $net_use_drive_letter")
            }
            else {
                cmdkey /delete:$net_use_server 2>$null | Out-Null
                cmdkey /add:$net_use_server /user:"Azure\$storage_account_name" /pass:$storage_account_key | Out-Null
                $net_use_output = net use * "$gallery_path"
                $net_use_drive_letter = ($net_use_output | Where-Object { $_ -match '([A-Z]):' } | Select-Object -First 1) -replace '^.*?([A-Z]:).*$', '$1'
                Write-Host("Drive letter is: $net_use_drive_letter")
            }
            $module_name = 'HelloWorld'
            $module_share_subfolder = 'ps-modules-gallery'
            $module_unc_gallery_path = Join-Path $gallery_path $module_share_subfolder
            $module_unc_gallery_nickname = 'VerifyUncGallery'
            Write-Host("Module UNC gallery path: $module_unc_gallery_path")
            try { Unregister-PSRepository -Name $module_unc_gallery_nickname -ErrorAction SilentlyContinue } catch {}
            Register-PSRepository `
                -Name $module_unc_gallery_nickname `
                -SourceLocation $module_unc_gallery_path `
                -PublishLocation $module_unc_gallery_path `
                -InstallationPolicy 'Trusted'
            Write-Host("Registered $module_unc_gallery_nickname")
        }
        It "should find at least 1 version of HelloWorld in the UNC gallery" {
            $found = Find-Module -Name $module_name -Repository $module_unc_gallery_nickname -AllVersions
            $found | Should -Not -BeNullOrEmpty
            $found.Count | Should -BeGreaterOrEqual 1
            Write-Host("Found $($found.Count) version(s): $($found.Version -join ', ')")
        }
        AfterAll {
            try { Unregister-PSRepository -Name $module_unc_gallery_nickname -ErrorAction SilentlyContinue } catch {}
            Write-Host("Unregistered $module_unc_gallery_nickname")
            if ($net_use_drive_letter) {
                net use $net_use_drive_letter /delete
            }
            if ($net_use_server) {
                cmdkey /delete:$net_use_server 2>$null | Out-Null
            }
            $net_use_drive_letter = $null
            $net_use_server = $null
            $net_use_output = $null
            $tfstate_file = $null
            $gallery_path = $null
            $storage_account_name = $null
            $storage_account_key = $null
            $module_name = $null
            $module_share_subfolder = $null
            $module_unc_gallery_path = $null
            $module_unc_gallery_nickname = $null
            Write-Host("Finished cleanup")
        }
    }
}

Describe "WinVM basic connectivity" -Skip {
    Describe "Validate Windows VM is up and loginnable as me" {
        # Once logged in, `(Get-ComputerInfo).OsManufacturer` should equal `Microsoft Corporation`
        It "should return correct remote OS manufacturer" {
            $remote_kernel_os_manufacturer = ( `
                    az vm run-command invoke `
                    --subscription "$([Environment]::GetEnvironmentVariable('DEMOS_my_azure_subscription_id', 'User'))" `
                    --resource-group "$([Environment]::GetEnvironmentVariable('DEMOS_my_workload_nickname', 'User'))-rg-demo" `
                    --name "$("$([Environment]::GetEnvironmentVariable('DEMOS_my_workload_nickname', 'User'))")WinVm" `
                    --command-id 'RunPowerShellScript' `
                    --scripts @("Get-ComputerInfo | Select-Object -Property 'OsManufacturer' -ExpandProperty 'OsManufacturer'") `
            )
            $remote_kernel_os_manufacturer_vm_weirdness_postprocessed = $remote_kernel_os_manufacturer `
            | ConvertFrom-Json `
            | Select-Object -Property 'value' -ExpandProperty 'value' `
            | Where-Object { $_.code -eq 'ComponentStatus/StdOut/succeeded' } `
            | Select-Object -First 1 `
            | Select-Object -Property 'message' -ExpandProperty 'message'
            $remote_kernel_os_manufacturer_vm_weirdness_postprocessed | Should -Not -BeNullOrEmpty
            $remote_kernel_os_manufacturer_vm_weirdness_postprocessed | Should -Be 'Microsoft Corporation'
        }
    }
    Describe "Validate Windows VM is up and loginnable over WinRM via admin username and password" {
        # Once logged in, `(Get-ComputerInfo).OsManufacturer` should equal `Microsoft Corporation`
        BeforeAll {
            $sessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck
            $tfstate_file = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, 'AA-tf', 'terraform.tfstate'))
            $win_vm_fqdn = (jq -r '.resources[] | select(.type=="github_actions_secret") | .instances[] | select(.attributes.secret_name=="THE_WINDOWS_VM_FQDN") | .attributes.plaintext_value' $tfstate_file)
            $win_vm_admin_username = (jq -r '.resources[] | select(.type=="github_actions_secret") | .instances[] | select(.attributes.secret_name=="THE_WINDOWS_VM_USERNAME") | .attributes.plaintext_value' $tfstate_file)
            $win_vm_admin_password = (jq -r '.resources[] | select(.type=="github_actions_secret") | .instances[] | select(.attributes.secret_name=="THE_WINDOWS_VM_PASSWORD") | .attributes.plaintext_value' $tfstate_file)
            $win_vm_admin_password_ss = ConvertTo-SecureString $win_vm_admin_password -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential ($win_vm_admin_username, $win_vm_admin_password_ss)
            $win_vm_admin_username = $null
            $win_vm_admin_password = $null
            $win_vm_admin_password_ss = $null
            $tfstate_file = $null
        }
        It "should return correct remote OS manufacturer" {
            $remote_kernel_os_manufacturer = Invoke-Command `
                -ComputerName $win_vm_fqdn `
                -Credential $cred `
                -UseSSL `
                -Port 5986 `
                -SessionOption $sessionOption `
                -ScriptBlock { Get-ComputerInfo | Select-Object -ExpandProperty 'OsManufacturer' }
            $remote_kernel_os_manufacturer | Should -Not -BeNullOrEmpty
            $remote_kernel_os_manufacturer | Should -Be 'Microsoft Corporation'
        }
    }
}

Describe "WinVM has D drive" -Skip {
    # Windows Azure VMs come with C, D, and E drives by default.
    BeforeAll {
        $get_disks_script = 'Get-CimInstance Win32_LogicalDisk | Select-Object DeviceID, VolumeName, FreeSpace'
        $disks = ( `
                az vm run-command invoke `
                --subscription "$([Environment]::GetEnvironmentVariable('DEMOS_my_azure_subscription_id', 'User'))" `
                --resource-group "$([Environment]::GetEnvironmentVariable('DEMOS_my_workload_nickname', 'User'))-rg-demo" `
                --name "$("$([Environment]::GetEnvironmentVariable('DEMOS_my_workload_nickname', 'User'))")WinVm" `
                --command-id 'RunPowerShellScript' `
                --scripts @($get_disks_script) `
        )
        $disks_postprocessed = $disks `
        | ConvertFrom-Json `
        | Select-Object -Property 'value' -ExpandProperty 'value' `
        | Where-Object { $_.code -eq 'ComponentStatus/StdOut/succeeded' } `
        | Select-Object -First 1 `
        | Select-Object -Property 'message' -ExpandProperty 'message'
        $disks_postprocessed_lines = $disks_postprocessed -split "`n"
    }
    It "is a 5-row sysout string (headers, divider, 3 drives, and two trailing lines)" {
        $disks_postprocessed_lines.Length | Should -Be 7
    }
    It "row beginning with C: has whitespace, 'Windows', whitespace" {
        $disks_postprocessed_lines `
        | Where-Object { $_ -match '^C:' } `
        | Should -Match '^C:\s+Windows\s+'
    }
    It "row beginning with D: has whitespace, 'Temporary Storage', whitespace" {
        $disks_postprocessed_lines `
        | Where-Object { $_ -match '^D:' } `
        | Should -Match '^D:\s+Temporary Storage\s+'
    }
}