ENUM Action{
        Extract
        #DeployReport
        #DriftReport
        Publish
        #Script
        #Export
        #Import
    }

Add-Type -AssemblyName System.Windows.Forms 

Add-Type -Path "C:\Program Files (x86)\Microsoft SQL Server\140\DAC\bin\Microsoft.SqlServer.Dac.dll"

Add-Type -Path "C:\Program Files (x86)\Microsoft SQL Server\140\DAC\bin\Microsoft.SqlServer.Dac.Extensions.dll"

$WorkingDir = "$PsScriptRoot" ;

#CleanDir
#Remove-Item "$WorkingDir\DACPACS" -Force -Recurse

New-Item -ItemType Directory -Path "$WorkingDir\DACPACS\EXTRACT" -Force | Out-Null;



$EnumNames = [Action].GetEnumNames();

$Form =  New-Object System.Windows.Forms.Form;
$ListBox = New-Object System.Windows.Forms.ListBox
$ListBox.Items.AddRange($EnumNames);
$ListBox.SelectedItem = "Publish";
$LabelTextBox = New-Object System.Windows.Forms.Label;
$LabelTextBox.Location = New-Object System.Drawing.Size(0,100)
$LabelTextBox.Text = 'ServerName'
$TextBox = New-Object System.Windows.Forms.TextBox;
$TextBox.Location = New-Object System.Drawing.Size(100,100)
$TextBox.Text = ".";
$OkButton = New-Object System.Windows.Forms.Button;
$OkButton.Text = 'OK';
$OkButton.Location = New-Object System.Drawing.Size(0,130 )
$OkButton.DialogResult = "OK";

$Form.Controls.Add($Textbox);
$Form.Controls.Add($LabelTextBox);
$Form.Controls.Add($ListBox);
$Form.Controls.Add($OkButton);
$result = $form.ShowDialog()
if ($result -eq "OK")
{
    $p_TargetServerName = $TextBox.Text;
    [Action]$p_Action = $listBox.SelectedItem
}





IF($p_Action -eq [Action]::Publish)
{
    $p_initialDirectory = ""

    $FolderBrowserDialog = New-Object System.Windows.Forms.FolderBrowserDialog

    $FolderBrowserDialog.SelectedPath = $p_initialDirectory
        #$OpenFileDialog.filter = "CSV (*.csv)| *.csv"
    $FolderBrowserDialog.ShowDialog() | Out-Null

    $ComboBoxForm = New-Object System.Windows.Forms.Form;
    
    $OkButton = New-Object System.Windows.Forms.Button;
    $OkButton.Text = 'OK';
    $OkButton.Location = New-Object System.Drawing.Size(300,50)
    $OkButton.DialogResult = "OK";

    $ComboBox = New-Object System.Windows.Forms.ListBox;
    $ComboBox.SelectionMode = "MultiExtended";

    $ComboBox.Items.AddRange((get-childitem -path $FolderBrowserDialog.SelectedPath -Recurse -Include "*.dacpac" | Select-Object Name | Sort-Object Name).Name);

    $ComboBox.AutoSize = $true;

    $ComboBoxForm.Controls.Add($ComboBox);

    $ComboBoxForm.Controls.Add($OkButton);

    $ComboBoxForm.AcceptButton = $OkButton;

    $ComboBoxForm.AutoSize = $true;

    $result = $ComboBoxForm.ShowDialog()
    if ($result -eq "OK")
    {
        $DacPacsFilter = $ComboBox.SelectedItems;
    }

    $DacPacs = get-childitem -path $FolderBrowserDialog.SelectedPath -Recurse -Include "*.dacpac"  | Where{$_.Name -in $DacPacsFilter} | Sort-Object Name -Descending

    Foreach($Dacpac in $DacPacs)
    {
    IF($Dacpac.BaseName -match "_DB")
    {
        $p_TargetDatabaseName = $Dacpac.BaseName.Substring(0,$Dacpac.BaseName.Length - 3);
    }
    ELSE
    {
        $p_TargetDatabaseName = $Dacpac.BaseName;
    };


    Start-Job -Name "$('Deploy_' + $p_TargetDatabaseName)" -ScriptBlock {
        param(  [string]$p_TargetServerName = $args[0]
                ,[string]$p_TargetDatabaseName = $args[1]
                ,[string]$p_DacPackage = $args[2]
                ,[string]$WorkingDir = $args[3])

        Add-Type -Path "C:\Program Files (x86)\Microsoft SQL Server\140\DAC\bin\Microsoft.SqlServer.Dac.dll"

        Add-Type -Path "C:\Program Files (x86)\Microsoft SQL Server\140\DAC\bin\Microsoft.SqlServer.Dac.Extensions.dll"

        $l_ConnectionString = "Data Source=$p_TargetServerName;Integrated Security=True;Persist Security Info=False;Pooling=False;MultipleActiveResultSets=False;Connect Timeout=60;Encrypt=False;TrustServerCertificate=True"

         [Microsoft.SqlServer.Dac.DacServices] $dbServices = new-object Microsoft.SqlServer.Dac.DacServices($l_ConnectionString)
        
        $l_DacPackage = [Microsoft.SqlServer.Dac.DacPackage]::Load($p_DacPackage);
   
        $l_DacPackage.Unpack("$WorkingDir\DACPACS\$p_TargetDatabaseName")

        $DacPublishOptions = New-Object Microsoft.SqlServer.Dac.PublishOptions
        $DacDeployOptions = New-Object Microsoft.SqlServer.Dac.DacDeployOptions

        $DacDeployOptions.CreateNewDatabase = $true;

        [xml]$XmlDoc = Get-Content("$WorkingDir\DACPACS\$p_TargetDatabaseName\model.xml")
        $XmlSqlCmdVariables = $XmlDoc.DataSchemaModel.Header.CustomData | Where-Object {$_.Category -eq "SqlCmdVariables"}

        foreach($SqlCmdVariable in $XmlSqlCmdVariables.Metadata)
        {
            $DacDeployOptions.SqlCommandVariableValues.Add($SqlCmdVariable.Name,$SqlCmdVariable.Name)
        }
        $DacPublishOptions.DeployOptions = $DacDeployOptions;
         TRY
         {
         $dbServices.Publish($l_DacPackage, $p_TargetDatabaseName, $DacPublishOptions)
         }
         CATCH #Catch If database already exists. Deploy instead
         {
         $dbServices.Deploy($l_DacPackage, $p_TargetDatabaseName, $false ,$DacDeployOptions)
         }
            } -ArgumentList @($p_TargetServerName,$p_TargetDatabaseName,$Dacpac.FullName,$WorkingDir)



    }

}
IF($p_Action -eq [Action]::Extract)
{


    $ComboBoxForm = New-Object System.Windows.Forms.Form;
    
    $OkButton = New-Object System.Windows.Forms.Button;
    $OkButton.Text = 'OK';
    $OkButton.Location = New-Object System.Drawing.Size(300,50 )
    $OkButton.DialogResult = "OK";

    $ComboBox = New-Object System.Windows.Forms.ListBox;
    $ComboBox.SelectionMode = "MultiExtended";
    $ComboBox.AutoSize = $true;

    $ComboBox.Items.AddRange((Get-SqlDatabase -ServerInstance $p_TargetServerName).Name);

    $ComboBoxForm.Controls.Add($ComboBox);

    $ComboBoxForm.Controls.Add($OkButton);

    $ComboBoxForm.AcceptButton = $OkButton;
    
    $ComboBoxForm.AutoSize = $true;

    $result = $ComboBoxForm.ShowDialog()
    if ($result -eq "OK")
    {
        $DatabaseFilter = $ComboBox.SelectedItems;
    }

    foreach($Database in $DatabaseFilter)
    {
        
        Start-Job -Name "$('Extract_' + $Database)" -ScriptBlock {
        param(  [string]$p_SourceServerName = $args[0]
                ,[string]$p_SourceDatabaseName = $args[1]
                ,[string]$WorkingDir = $args[2])

        Add-Type -Path "C:\Program Files (x86)\Microsoft SQL Server\140\DAC\bin\Microsoft.SqlServer.Dac.dll"

        Add-Type -Path "C:\Program Files (x86)\Microsoft SQL Server\140\DAC\bin\Microsoft.SqlServer.Dac.Extensions.dll"

        $l_ConnectionString = "Data Source=$p_SourceServerName;Integrated Security=True;Persist Security Info=False;Pooling=False;MultipleActiveResultSets=False;Connect Timeout=60;Encrypt=False;TrustServerCertificate=True"

         [Microsoft.SqlServer.Dac.DacServices] $dbServices = new-object Microsoft.SqlServer.Dac.DacServices($l_ConnectionString)

         $dbServices.Extract("$WorkingDir\DACPACS\EXTRACT\$($p_SourceDatabaseName)_DB.dacpac","$p_SourceDatabaseName","$($p_SourceDatabaseName)_DB","1.0.0.0", $null, $null, $null, $null)

        } -ArgumentList @($p_TargetServerName,$Database,$WorkingDir)



    }
    

}
Wait-Job -State Running | Out-Null;
foreach($Job in Get-Job -State Completed)
{
Receive-Job -Job $Job
}

