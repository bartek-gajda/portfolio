#!/usr/bin/env pwsh

# Script for udating or deleting tags - based on data taken from csv file
#
# script is working in two modes: Read-only and Write
# after starting the script, user is asked about the mode and should make a choice 
# Read mode - only print current vm.LicenseType
# Write mode 
#  provided from the csv file with tag value
# 
# usage:
#
# ./update-vm-tag.ps1 <csv file>
#
# requirements:
# csv file provided as the parameter with the following format:
# vm-name;subscription_name;RG_name;tag_value
# and only 4 first values are taken, 5th or next values after ; are skipped
#

# initial tag name, it don't need to be updated, user is asked about it in the script     
$TAG_KEY = ""

# asking about which tag to process
$title_tag    = 'First you can decide which tag to process'
$question_tag = 'Choose the tag?'

$Choices_tag = @(
    [System.Management.Automation.Host.ChoiceDescription]::new("&1 automated_start", "automated_start"),
    [System.Management.Automation.Host.ChoiceDescription]::new("&2 automated_stop", "automated_stop"),
    [System.Management.Automation.Host.ChoiceDescription]::new("&3 automated_excl", "automated_excl")
    [System.Management.Automation.Host.ChoiceDescription]::new("&4 enter own custom tag", "enter own custom tag")
)


$decision_tag = $Host.UI.PromptForChoice($title_tag, $question_tag, $choices_tag, -1)

switch ($decision_tag)
{
    0 { $TAG_KEY = "automated_start" }
    1 { $TAG_KEY = "automated_stop" }
    2 { $TAG_KEY = "automated_excl" }
    3 { $TAG_KEY = Read-Host -Prompt "Input tag name"}
}

Write-Host "Your choice: " $TAG_KEY 
Write-Host ""

$title    = ''
$question = 'Choose the mode to continue?'
#$choices  = '&Read-only tags values','&Write tags'

$Choices = @(
    [System.Management.Automation.Host.ChoiceDescription]::new("&Read tags values", "Read tags values")
    [System.Management.Automation.Host.ChoiceDescription]::new("&Write tag", "Write tag")
)

$decision = $Host.UI.PromptForChoice($title, $question, $choices, -1)
Write-Host ""

# asking if check also VM powerstate - it is a slower process
$title2    = ''
$question2 = 'Do you want to check the VM state (SLOWER processing)?'
#$choices  = '&Read-only tags values','&Write tags'

$Choices2 = @(
    [System.Management.Automation.Host.ChoiceDescription]::new("&Y", "Yes")
    [System.Management.Automation.Host.ChoiceDescription]::new("&N", "No")
)
$check_state = $Host.UI.PromptForChoice($title2, $question2, $choices2, -1)

# assign argument from user cli to a $serverList variable
$ServerList = $args[0]
$discrepancies_detected = 0

$subscription_list = [System.Collections.ArrayList]::new()
$vm_list_from_csv = [System.Collections.ArrayList]::new()
$vm_list_from_azure = [System.Collections.ArrayList]::new()  
$vm_list_discrepancies = [System.Collections.ArrayList]::new()
$output = @()

function build_vm_list_from_input_csv_file {
    try     {
        Get-Content $ServerList | ForEach-Object {
            $vm_name = $_.Split(";")[0].ToUpper()
            $sub = $_.Split(";")[1].ToUpper()
            $rg = $_.Split(";")[2].ToUpper()
            $tag = $_.Split(";")[3]
            $vm_list_from_csv.Add(@($vm_name,$sub,$rg,$tag)) | Out-Null
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
        # $i is added as the position number
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
    # $row_no - is taken from added position of row number in csv file
    $row_no = $vm_item_discrepancies[3] 
    # changening columns - godd (from azure) with a wrong (from csv file)
    $vm_list_from_csv[$row_no][2] = $vm_item_discrepancies[1]
  }
}

function build_result_in_table {
  # we need to querry about vm again because it just has tag updated after last Get-AzVM check
  $vm = Get-AzVM -ResourceGroup $rg -Name $vm_name
  if ($check_state -eq 0) {
    #user answered Y to ckeck VM state
    $vm_state = (Get-AzVM -Name $vm_name -status).powerstate
    $newitem = [PSCustomObject]@{ Name = $vm_name ; Subscription = $sub ; RG = $rg ; $TAG_KEY = $vm.Tags[$TAG_KEY] ; State = $vm_state}
    $script:output += $newitem
  }
  else {
    # userd answered N - ndo not want to check VM state
    $newitem = [PSCustomObject]@{ Name = $vm_name ; Subscription = $sub ; RG = $rg ; $TAG_KEY = $vm.Tags[$TAG_KEY]}
    $script:output += $newitem
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
        Write-Host "Name             Subscription                      Resource Group               TAG: "$TAG_KEY -ForegroundColor Yellow -BackgroundColor Black
        Write-Host "====             =============                     ==============               ====================" -ForegroundColor Green -BackgroundColor Black
        $vm_list_from_csv | ForEach-Object {
          #Write-Host("_=",$_)
          #$vm_name = $_.Split(";")[0]
          $vm_name = $_[0]
          #Write-Host("vm_name=",$vm_name)
          #$sub = $_.Split(";")[1]
          $sub = $_[1]
          #Write-Host("sub=",$sub)
          #$rg = $_.Split(";")[2]
          $rg = $_[2]
          #Write-Host("rg=",$rg)

          # building list of subscriptions
          if (-not $subscription_list.Contains($sub)) {
              $subscription_list.Add($sub)
          }         
           if ((Get-AzContext).Subscription.name -ne $sub) {
              Set-AzContext -Subscription $sub | Out-Null
           }
           $vm = Get-AzVM -ResourceGroup $rg -Name $vm_name
           printf "%s" $vm.Name "    " $sub "     " $rg
           if ($vm.Tags.ContainsKey($TAG_KEY)) {
              printf "%s"  "   "$vm.Tags[$TAG_KEY]"`n"
	            build_result_in_table
           }
           else
           {
            Write-Host " " $TAG_KEY " - is missing"  -NoNewLine
            Write-Host ""
            build_result_in_table
           }
           if (-not $sub -or -not $rg) {
             Write-Output "data missing in csv file"
             continue
           }
        }
       
        Write-host "`n==================== SUMMARY: printing again in a table format ====================" -ForegroundColor Yellow -BackgroundColor Black
        $output | Format-Table
       }
    1 {
        Write-Host "Name             Subscription                      Resource Group               TAG: " $TAG_KEY -ForegroundColor Yellow -BackgroundColor Black
        Write-Host "====             =============                     ==============               ====================" -ForegroundColor Green -BackgroundColor Black
        $vm_list_from_csv | ForEach-Object {
            $vm_name = $_[0]
            $sub = $_[1]
            $rg = $_[2]
            $tag_new_value = $_[3]
         
       
         Set-AzContext -Subscription $sub | Out-Null
         $vm = Get-AzVM -ResourceGroup $rg -Name $vm_name
         if (-not $sub -or -not $rg) {
           Write-Output "data missing in csv file"
           continue
         }
         # if provided tag in csv in a row in file is empty - it means it will be deleted
         if ( ($vm.Tags.ContainsKey($TAG_KEY)) -and (($tag_new_value -eq $null) -or ($tag_new_value.length -eq 0))) {
            $deletetag = @{$TAG_KEY=$vm.Tags.($TAG_KEY)}
            #Write-Host ("deletetag=",$deletetag)
            write-Host $vm.name " " $sub " " $rg " " -NoNewLine
            printf "%s"  "   to remove: "$TAG_KEY "="$vm.Tags["$TAG_KEY"]"`n"
            # Delete the tag from the VM
            Update-AzTag -ResourceId $vm.Id -Tag $deletetag -Operation Delete | Out-Null
              build_result_in_table           
          }
         # if tag is not empty - it will be updated, sometimes value can be like "" so checking lenght
         elseif (($tag_new_value -ne $null) -and ($tag_new_value.length -ne 0)) {
            #Write-Host("tag_new_value=",$tag_new_value,".",$tag_new_value.length)
            $updatetag = @{$TAG_KEY=$tag_new_value}
            write-Host "updating: ",$vm.name " " $sub " " $rg " " -NoNewLine
            write-Host $updatetag.$TAG_KEY -NoNewLine
            write-Host ""
            Update-AzTag -ResourceId $vm.Id -Tag $updatetag -Operation Merge | Out-Null
            build_result_in_table
         }
         else
         {
            write-Host $vm.name " " $sub " " $rg " " -NoNewLine
            Write-Host " " $TAG_KEY " - is missing - skipping"  -NoNewLine
            Write-Host ""
            build_result_in_table
         }
         
       }
    Write-host "`n==================== SUMMARY: printing again in a table format ====================" -ForegroundColor Yellow -BackgroundColor Black
    $output | Format-Table
    }
    Default {}
}
