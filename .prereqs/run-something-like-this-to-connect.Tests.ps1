Describe "Basic file share operations work by UNC" {
    BeforeAll {
        $storage_account_name = "$([Environment]::GetEnvironmentVariable('DEMOS_my_workload_nickname', 'User'))storacct"
        $storage_account_key = az storage account keys list `
            --subscription "$([Environment]::GetEnvironmentVariable('DEMOS_my_azure_subscription_id', 'User'))" `
            --resource-group "$([Environment]::GetEnvironmentVariable('DEMOS_my_workload_nickname', 'User'))-rg-demo" `
            --account-name $storage_account_name `
            --query '[0].value' `
            --output 'tsv'
        $tfstate_file = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, 'AA-tf', 'terraform.tfstate'))
        $gallery_path = (jq -r '.resources[] | select(.type=="github_actions_variable") | .instances[] | select(.attributes.variable_name=="THE_STORACCT_SHAREPATH") | .attributes.value' $tfstate_file) # UNC of format "\\fqdn\subfolder"
        Write-Host("Gallery path is:  $gallery_path")
        $existing_net_use_line = net use | Where-Object { $_ -match [regex]::Escape($gallery_path) } | Select-Object -First 1
        if ($existing_net_use_line -and $existing_net_use_line -match '([A-Z]):') {
            $net_use_drive_letter = $Matches[1] + ':'
            Write-Host("Reusing existing net use drive letter: $net_use_drive_letter")
        }
        else {
            $net_use_output = net use * "$gallery_path" "/user:Azure\$([Environment]::GetEnvironmentVariable('DEMOS_my_workload_nickname', 'User'))storacct" $storage_account_key
            $net_use_drive_letter = ($net_use_output | Where-Object { $_ -match '([A-Z]):' } | Select-Object -First 1) -replace '^.*?([A-Z]:).*$', '$1'
            Write-Host("Drive letter is:  $net_use_drive_letter")
        }
    }
    It "should be reachable as a UNC path" {
        Test-Path $gallery_path | Should -BeTrue
    }
    It "should allow listing contents" {
        { Get-ChildItem $gallery_path } | Should -Not -Throw
    }
    It "should allow creating and deleting a file" {
        $testFile = Join-Path $gallery_path 'testfile.txt'
        Set-Content -Path $testFile -Value 'test' -Force
        Test-Path $testFile | Should -BeTrue
        Remove-Item $testFile -Force
        Test-Path $testFile | Should -BeFalse
    }
    Describe "PowerShell should work too" {
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
            $az_upload_share_name = ($gallery_path -split '\\' | Where-Object { $_ -ne '' })[1]
            $az_upload_test_subfolder = 'az-upload-test'
            $az_upload_test_filename = "az-rest-upload-$(Get-Date -Format 'yyyyMMddHHmmss').txt"
            $az_upload_local_dir = Join-Path $env:TEMP 'az-upload-test-source'
            New-Item -ItemType Directory -Force -Path $az_upload_local_dir | Out-Null
            $az_upload_local_file = Join-Path $az_upload_local_dir $az_upload_test_filename
            Set-Content -Path $az_upload_local_file -Value "Uploaded via az storage file upload-batch at $(Get-Date -Format 'o')" -Force
            # Parse share name from UNC path: \\server\share -> last non-empty segment
            Write-Host("Share name parsed from UNC: $az_upload_share_name")
            az storage file upload-batch `
                --subscription "$([Environment]::GetEnvironmentVariable('DEMOS_my_azure_subscription_id', 'User'))" `
                --account-name $storage_account_name `
                --destination $az_upload_share_name `
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
            $az_upload_share_name = $null
            Write-Host("Finished az upload test cleanup")
        }
    }
    AfterAll {
        net use $net_use_drive_letter /delete
        $net_use_drive_letter = $null
        $net_use_output = $null
        $tfstate_file = $null
        $gallery_path = $null
        $storage_account_key = $null
        $storage_account_name = $null
        Write-Host("Finished cleanup")
    }
}