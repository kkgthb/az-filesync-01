Describe "Basic file share operations work by UNC" {
    BeforeAll {
        $storage_account_key = az storage account keys list `
            --subscription "$([Environment]::GetEnvironmentVariable('DEMOS_my_azure_subscription_id', 'User'))" `
            --resource-group "$([Environment]::GetEnvironmentVariable('DEMOS_my_workload_nickname', 'User'))-rg-demo" `
            --account-name "$([Environment]::GetEnvironmentVariable('DEMOS_my_workload_nickname', 'User'))storacct" `
            --query '[0].value' `
            --output 'tsv'
        $tfstate_file = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, 'AA-tf', 'terraform.tfstate'))
        $gallery_path = (jq -r '.resources[] | select(.type=="github_actions_variable") | .instances[] | select(.attributes.variable_name=="THE_STORACCT_SHAREPATH") | .attributes.value' $tfstate_file) # UNC of format "\\fqdn\subfolder"
        Write-Host("Gallery path is:  $gallery_path")
        $net_use_output = net use * "$gallery_path" "/user:Azure\$([Environment]::GetEnvironmentVariable('DEMOS_my_workload_nickname', 'User'))storacct" $storage_account_key
        $net_use_drive_letter = ($net_use_output | Select-String -Pattern '[A-Z]:').Matches[0].Value
        Write-Host("Drive letter is:  $net_use_drive_letter")
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
    AfterAll {
        net use $net_use_drive_letter /delete
        $net_use_drive_letter = $null
        $net_use_output = $null
        $tfstate_file = $null
        $gallery_path = $null
        $storage_account_key = $null
        Write-Host("Finished cleanup")
    }
}