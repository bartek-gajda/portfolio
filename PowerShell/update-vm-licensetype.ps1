#!/usr/bin/env pwsh

# script is designed for providing license to VMs in Azure Hybrid Benefit
# docs:
# https://learn.microsoft.com/en-us/azure/virtual-machines/windows/hybrid-use-benefit-licensing
#
#
# usage:
# update-vm-licensetype.ps1 <csv file>
#
# script is working in two modes: Read-only and Write
# after starting the script, user is asked about the mode and should make a choice 
# Read mode - only print current vm.LicenseType
# Write mode - requires PIM activation before, it updates list of VMs 
#  provided from the csv file with vm.LicenseType="Windows_Server"
# 
# requirements:
# csv file provided as the parameter with the following format:
# vm-name;RG_name;subscription_name
# and only 3 first values are taken, 4th or next values after ; are skipped



#### CHANGE this code below to 1. or 2.:
#  1. to assign Windows server license:
#       $new_LicenseType = "Windows_Server"
#  2. to delete license:
#       $new_LicenseType = "None"
### change the line here below:       
$new_LicenseType = "None"

$title    = 'Updating VM license - Value of VMs - vm.LicenseType='+$new_LicenseType
$question = 'Choose the mode to continue?'
#$choices  = '&Read-only licences values','&Write license'

$Choices = @(
    [System.Management.Automation.Host.ChoiceDescription]::new("&Read licences values", "Read licences values")
    [System.Management.Automation.Host.ChoiceDescription]::new("&Write license", "Write license")
)

$decision = $Host.UI.PromptForChoice($title, $question, $choices, -1)


$ServerList = $args[0]
$discrepancies_detected = 0

Write-Output $ServerList

$subscription_list = [System.Collections.ArrayList]::new()
$vm_list_from_csv = [System.Collections.ArrayList]::new()
$vm_list_from_azure = [System.Collections.ArrayList]::new()  
$vm_list_discrepancies = [System.Collections.ArrayList]::new()

function build_vm_list_from_input_csv_file {
    try     {
        Get-Content $ServerList | ForEach-Object {
            $vm_name = $_.Split(";")[0].ToUpper()
            $sub = $_.Split(";")[1].ToUpper()
            $rg = $_.Split(";")[2].ToUpper()
            $vm_list_from_csv.Add(@($vm_name,$sub,$rg)) | Out-Null
            # building list of subscriptions
            if (-not $subscription_list.Contains($sub)) {
                $subscription_list.Add($sub) | Out-Null
            }
        }
    }
    catch {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

function build_vm_list_from_azure {
    try     {
        foreach ($sub_item in $subscription_list) {
            Set-AzContext -Subscription $sub_item | Out-Null
            $vm_list_temp = Get-AzVM 
            foreach ($vm_item in $vm_list_temp) {
            $vm_list_from_azure.Add(@($vm_item.Name.ToUpper(),$sub_item.ToUpper(),$vm_item.ResourceGroupName.ToUpper())) | Out-Null
            }
            
        }
    }
    catch {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }    
}

function investigate_discrepancies  {
  #Write-Output " checking discrepancies"
  # $i - is for remembering row position in csv where we found discrepancy
  $i = 0
  foreach ($vm_item_from_csv in $vm_list_from_csv) {
    foreach ($vm_item_in_azure in $vm_list_from_azure) {
      # checking if VM name is the same and subscription is the same but RG name is different
      if (($vm_item_in_azure[0] -eq $vm_item_from_csv[0]) -and ($vm_item_in_azure[1] -eq $vm_item_from_csv[1]) -and ($vm_item_in_azure[2] -ne $vm_item_from_csv[2]) ) {
        $vm_list_discrepancies.Add(@($vm_item_in_azure[0],$vm_item_in_azure[2],$vm_item_from_csv[2],$i)) | Out-Null
      }
      if (($vm_item_in_azure[0] -eq $vm_item_from_csv[0]) -and ($vm_item_in_azure[2] -eq $vm_item_from_csv[2]) ) {
      }
    }
    $i = $i+1
  }
  if ($vm_list_discrepancies.count -gt 0) {
    Write-Host "== discrepancies  found !! ==" -ForegroundColor Red -BackgroundColor Black
    Write-Host "CSV file contains different RG names than expected in Azure" -ForegroundColor White -BackgroundColor Black
    Write-Host "Please check carefully disrepancies below: " -ForegroundColor White -BackgroundColor Black
    $vm_list_discrepancies  | ForEach-Object { [PSCustomObject]@{'vm.name'=$_[0]; 'RG name in Azure'=$_[1]; 'RG name in CSV file'=$_[2]; 'Row in csv'=$_[3]+1} } | Format-Table
    $script:discrepancies_detected = 1
  }
  else {
    $script:discrepancies_detected = 0
  }
}

function correct_discrepancies {
  # function correct $vm_list_from_csv based on $vm_list_discrepancies
  foreach ($vm_item_discrepancies in $vm_list_discrepancies) {
    # reading 
    $row_no = $vm_item_discrepancies[3] 
    $vm_list_from_csv[$row_no][2] = $vm_item_discrepancies[1]
  }
}

Write-Output " building vm list from csv file"
build_vm_list_from_input_csv_file

Write-Output " building vm list from azure, please wait a moment..."
build_vm_list_from_azure

Write-Output ""
investigate_discrepancies

if ($discrepancies_detected -eq 1) {
  $userInput = Read-Host  "Do you want to correct disrepencies Y/N ?"
  if ($userInput -eq "y") {
    Write-Host "CSV file " -ForegroundColor Yellow -BackgroundColor Black
    $vm_list_from_csv | ForEach-Object { [PSCustomObject]@{'vm.name'=$_[0]; 'Subscription'=$_[1]; 'RG '=$_[2]; } } | Format-Table
    correct_discrepancies
    Write-Host "VM list after correcting RG" -ForegroundColor Green -BackgroundColor Black
    $vm_list_from_csv | ForEach-Object { [PSCustomObject]@{'vm.name'=$_[0]; 'Subscription'=$_[1]; 'RG '=$_[2]; } } | Format-Table
  }
}

switch ($decision)
{
    0 {
        Write-Host "Name             Subscription                      Resource Group               LicenseType" -ForegroundColor Yellow -BackgroundColor Black
        Write-Host "====             =============                     ==============               ===========" -ForegroundColor Green -BackgroundColor Black
        $vm_list_from_csv | ForEach-Object {
            $vm_name = $_.Split(";")[0]
            $sub = $_.Split(";")[1]
            $rg = $_.Split(";")[2]
         
            # building list of subscriptions
            if (-not $subscription_list.Contains($sub)) {
                $subscription_list.Add($sub)
            }
       
            Set-AzContext -Subscription $sub | Out-Null
            $vm = Get-AzVM -ResourceGroup $rg -Name $vm_name
         
            printf "%s" $vm.Name "    " $sub "     " $rg "     " $vm.LicenseType  "`n"
            if (-not $sub -or -not $rg) {
                Write-Output "data missing in csv file"
                continue
            }
        }
        
       }
    1 {
        Write-Host "Name             Subscription                      Resource Group               LicenseType" -ForegroundColor Yellow -BackgroundColor Black
        Write-Host "====             =============                     ==============               ===========" -ForegroundColor Green -BackgroundColor Black
        $vm_list_from_csv | ForEach-Object {
            $vm_name = $_.Split(";")[0]
            $sub = $_.Split(";")[1]
            $rg = $_.Split(";")[2]
         
            Set-AzContext -Subscription $sub | Out-Null
            $vm = Get-AzVM -ResourceGroup $rg -Name $vm_name
            if (-not $sub -or -not $rg) {
                Write-Output "data missing in csv file"
                continue
            }
            $vm.LicenseType = $new_LicenseType
            Update-AzVM -ResourceGroupName $rg -VM $vm
            printf "%s" $vm.Name "    " $sub "     " $rg "     " $vm.LicenseType  "`n"
       }
    }
    Default {}
}
