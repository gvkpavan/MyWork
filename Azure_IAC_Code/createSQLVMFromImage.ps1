$envName = $env:EnvName

$VMParamscsvFile = $psscriptroot + '\SQLVMfromImage_Params_'+ $envName +'.csv'
$VMARMTemplateFile = $psscriptroot + '\CreateSQLVMfromImage.json'

# Read CSV File Input parameters
    if (!(Test-Path $(split-path $VMParamscsvFile)))
        {
            Write-Verbose 'CSV File does not exist'
        }
    else 
        {
            $CSVJobs = Import-CSV -Path $VMParamscsvFile
            Write-Verbose 'Successfully imported CSV File.'
            Start-Sleep -Seconds 3            
        }

    $PSJobs1 = @()
    
    ForEach ($CSVJob in $CSVJobs)
    {   
            Get-AzureRmVM -Name $($CSVJob.customVmName).Trim() -ResourceGroupName $($CSVJob.virtualMachineRG).Trim() -ErrorVariable notPresent -ErrorAction silentlyContinue

            if($notPresent)
            {                    
            $adminPwd = Get-AzureKeyVaultSecret -VaultName $($CSVJob.keyVaultName).Trim() -Name $($CSVJob.defaultPwdSecret).Trim() 
            $domainPwd = Get-AzureKeyVaultSecret -VaultName $($CSVJob.keyVaultName).Trim() -Name $($CSVJob.domainPwdSecret).Trim()
            $omsId = Get-AzureKeyVaultSecret -VaultName $($CSVJob.keyVaultName).Trim() -Name $($CSVJob.omsIdSecret).Trim()
            $omsKey = Get-AzureKeyVaultSecret -VaultName $($CSVJob.keyVaultName).Trim() -Name $($CSVJob.omsWorkspaceKeySecret).Trim()
            $domainJoinOptions = [int] ($($CSVJob.domainJoinOption).Trim())

            $paramList = @{                 
                customVmName = $($CSVJob.customVmName).Trim()
                imageResourceGroup = $($CSVJob.imageResourceGroup).Trim()
                imageName = $($CSVJob.imageName).Trim()
                location = $($CSVJob.location).Trim()
                virtualMachineRG = $($CSVJob.virtualMachineRG).Trim()
                osDiskType = $($CSVJob.osDiskType).Trim()
                adminUsername = $($CSVJob.adminUserName).Trim()
                adminPassword = $adminPwd.SecretValueText
                virtualMachineSize = $($CSVJob.virtualMachineSize).Trim()
                vNetResourceGroup = $($CSVJob.vNetResourceGroup).Trim()
                virtualNetworkName = $($CSVJob.virtualNetworkName).Trim()
                subnetName = $($CSVJob.subnetName).Trim()  
                OMSWorkspaceID = $omsId.SecretValueText
                OMSWorkspaceKey = $omsKey.SecretValueText
                domainToJoin = $($CSVJob.domainToJoin).Trim()
                domainUsername = $($CSVJob.domainUsername).Trim()
                domainPassword = $domainPwd.SecretValueText
                domainJoinOptions = $domainJoinOptions
                privateIPAddress = $($CSVJob.privateIP).Trim()
                availabilitySetName = $($CSVJob.availabilitySet).Trim()
                loadBalancerName = $($CSVJob.internalLB).Trim()
                diagStorageAccountName = $($CSVJob.diagStorageAccountName).Trim()                
                }
                
                $PSJobs1 += New-AzureRmResourceGroupDeployment -ResourceGroupName  $CSVJob.virtualMachineRG `
                     -TemplateFile $VMARMTemplateFile `
                     -TemplateParameterObject $paramList -Name $CSVJob.customVmName -AsJob

            }
            else
            {
                Write-Verbose "Already Exists"
            }
    }

# Get output of all jobs
Get-Job -State Suspended | Resume-Job
Start-Sleep -s 30

$PSJobs1 | Get-Job | Wait-Job

# Add VM as DSC Node to make it comply with APS standards and CIS Sec Rules

$scriptblock = {
    Register-AzureRmAutomationDscNode -AutomationAccountName $args[0] -ResourceGroupName $args[1] `
    -nodeConfigurationName $args[4] -AzureVMName $args[2] -AzureVMResourceGroup $args[3] -AzureVMLocation $args[5] `
    -ConfigurationMode ApplyAndAutocorrect -AllowModuleOverwrite $true;
    }

ForEach ($CSVJob in $CSVJobs)
{            
        $AutomationAccountName = $($CSVJob.AutomationAccountName).Trim()
        $AAResourceGroupName = $($CSVJob.AAResourceGroup).Trim()
        $VMName = $($CSVJob.customVmName).Trim()
        $VMResourceGroup = $($CSVJob.virtualMachineRG).Trim()
        $NodeConfigurationname = $($CSVJob.NodeConfigurationname).Trim()
      
        $rg = Get-AzureRmResourceGroup -Name $AAResourceGroupName
        $location = $rg.Location
        
        $args = @($AutomationAccountName,$AAResourceGroupName,$VMName,$VMResourceGroup,$NodeConfigurationname,$location)
$args
        #Register Node with Azure Automation Account Dsc
        #Start-Job -ScriptBlock $scriptblock -ArgumentList $args 
        Register-AzureRmAutomationDscNode -AutomationAccountName $args[0] -ResourceGroupName $args[1] `
    -nodeConfigurationName $args[4] -AzureVMName $args[2] -AzureVMResourceGroup $args[3] -AzureVMLocation $args[5] `
    -ConfigurationMode ApplyAndAutocorrect -AllowModuleOverwrite $true;
     
} 
# Get output of all jobs
#Get-Job | Wait-Job
#"All jobs completed"
