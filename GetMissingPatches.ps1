<#
.Synopsis
    Install missing patches on the system
.DESCRIPTION 
    This script will check for missing patches on the system using mbsacli and create a .bat file to automate the installation of those patches
    The script requires the following mbsa files:
        -Mbsacli.exe
        -wsusscn2.dll
        -wsusscn2.cab
    The files MUST be stored on the same folder
.EXAMPLE
    This command will check for missing patches and list them. Additionally it will generate .bat script to patch the system automatically
    ./GetMissingPatches -mbsaFolder C:\temp -outputFolder C:\temp 
.EXAMPLE
    The -download switch will download missing patches automatically and strore them in C:\temp\patches folder
    ./GetMissingPatches -mbsaFolder C:\temp -outputFolder C:\temp -download
.EXAMPLE 
    The -importResultsXML will import results.xml files generated on isolated environments that doesn't allow to download updates
    ./GetMissingPatches -importResultsXML C:\temp\results.xml
#>


Param (
    
    [string]$importResultsXML,
    
    #[Parameter(Mandatory=$False,Position=1)]
    [string]$mbsaFolder= "C:\temp",
    
    #[Parameter(Mandatory=$False,Position=2)]
    [string]$outputFolder="C:\temp",
        
    
    #[Parameter(Mandatory=$False,Position=3)]
    [switch]$download   
      
)

Write-Host "All information generated by the script will be stored in C:\temp"
Write-Host ""

#Checking parameters
if ($PSBoundParameters.ContainsKey('download')){
    $download=$True
    Write-Host "******************Download mode active******************"
 }
 
 
$patchesFolder = $outputFolder + "\patches\"
$installFile = $outputFolder +”\Install_patches.bat”
New-Item -type directory -Force -Path $outputFolder | Out-NUll
New-Item -type directory -Force -Path $patchesFolder  | Out-Null



##Check if wsusscn2.cab is up to date
$wsusscn2_url="http://go.microsoft.com/fwlink/?LinkID=74689"
$wsusscn2_path= $mbsaFolder + "\wsusscn2.cab"
$mbsacli_path= $mbsaFolder + "\mbsacli.exe"
$system_date= Get-Date
$wsus_date = [datetime]((Get-ItemProperty -Path $wsusscn2_path -Name LastWriteTime).lastwritetime)
$Days = (New-TimeSpan -Start $system_date -End $wsus_date).Days

if ($Days -lt -15)
    {
        Write-Host "wsusscn2 has not been updated whithin 15 days and could be out of date"
        $in = Read-Host "Do you want to update the wsusscn2.cab file right now [Y|n]:"
        if ($in -eq "Y" -or $in -eq ''){
            $wc = New-Object System.Net.WebClient
            Write-host "Downloading file, this might take a while..."
            $wc.DownloadFile($wsusscn2_url,$wsusscn2_path)
            Write-Host "File download successfully"
        }
        else{
        Write-Host "skipping wsusscn2.cab update"
        }
    }


#if not importing previous results, then execute mbsacli
if (!$PSBoundParameters.ContainsKey('importResultsXML'))
    {
        Write-Host "Checking for missing patches, this may take a while..."
        cmd.exe /c $mbsacli_path /catalog $wsusscn2_path /xmlout > C:\temp\results.xml
        $UpdateXML = "C:\temp\results.xml"   
    }
else
    {
     $UpdateXML = $importResultsXML
    } 
       
    #Initialize webclient for downloading files
     $webclient = New-Object Net.Webclient
     $webClient.UseDefaultCredentials = $true

    #Get the content of the XML file
     $Updates = [xml](Get-Content $UpdateXML)

“@Echo Off” | Out-File $installFile
“REM This script will install missing patches on the system” | Out-File $installFile -Append

# for each patch check if it's installed on the system

foreach ($Check in $Updates.XMLOut.Check)
 {
    Write-Host “Checking for”, $Check.Name
    Write-Host $Check.Advice.ToString()

    #Checking for files to download
    foreach ($UpdateData in $Check.Detail.UpdateData)
     {
        if ($UpdateData.IsInstalled -eq $false)
            {
              $PatchID = $updateData.ID.ToString()
              Write-Host "The patch $PatchID is not installed on the system"
              if ($PSBoundParameters.ContainsKey('download')){  
                Write-Host “Download the file for KB”, $UpdateData.KBID
                Write-Host “Starting download “, $UpdateData.Title, “.”
                $url = [URI]$UpdateData.References.DownloadURL
                $fileName = $url.Segments[$url.Segments.Count – 1]
                Write-Host $fileName
                $toFile = $outputFolder +”\patches\”+ $fileName
                $webClient.DownloadFile($url, $toFile)
                Write-Host “Done downloading”

                “@ECHO Starting installing “+ $fileName | Out-File $installFile -Append
                    if ($fileName.EndsWith(“.msu”))
                        {
                            “wusa.exe “+ $fileName + ” /quiet /norestart /log:%SystemRoot%\Temp\KB”+$UpdateData.KBID+”.log” | Out-File $installFile -Append
                        }
                    elseif ($fileName.EndsWith(“.cab”))
                        {
                            “start /wait pkgmgr.exe /ip /m:”+ $fileName + ” /quiet /nostart /l:%SystemRoot%\Temp\KB”+$UpdateData.KBID+”.log” | Out-File $installFile -Append
                        }
                    else
                        {
                             $fileName + ” /passive /norestart /log %SystemRoot%\Temp\KB”+$UpdateData.KBID+”.log” | Out-File $installFile -Append
                        }
                             “@ECHO Installation returned %ERRORLEVEL%” | Out-File $installFile -Append
                             “@ECHO.” | Out-File $installFile -Append
                             Write-Host
               }
            }
        }

    Write-Host 
}

Write-Host "Job done!"
