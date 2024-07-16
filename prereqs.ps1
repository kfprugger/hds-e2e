# Prerequisites
## Ensure you have the following installed on your machine:

### Azure PowerShell Module
if (-not (Get-Module -ListAvailable -Name Az)) {
    Write-Host "Azure PowerShell module is not installed. Please install it before proceeding."
    break
} else {
    Write-Host "Azure PowerShell module is installed. Continuing with the script."
}

### Azure CLI
if (-not (Get-Module -ListAvailable -Name Az)) {
    Write-Host "Azure CLI is not installed. Installing it now."
    Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi
    Start-Process -Wait -FilePath .\AzureCLI.msi
    Remove-Item .\AzureCLI.msi
    Write-Host "Azure CLI installation completed. Continuing with the script."
} else {
    Write-Host "Azure PowerShell module is installed. Continuing with the script."
}

### Docker Desktop
if (-not (Get-Command "docker" -ErrorAction SilentlyContinue)) {
    Write-Host "Docker Desktop is not installed. Installing it now."
    Invoke-WebRequest -Uri https://desktop.docker.com/win/stable/Docker%20Desktop%20Installer.exe -OutFile .\DockerDesktopInstaller.exe
    Start-Process -Wait -FilePath .\DockerDesktopInstaller.exe
    Remove-Item .\DockerDesktopInstaller.exe
    Write-Host "Docker Desktop installation completed. Continuing with the script."
} else {
    Write-Host "Docker Desktop is installed. Continuing with the script."
}

#### Ensure Docker is running and switch to Linux Containers
$docker = docker ps 2>&1
if ($docker -match '^(?!error)') {
    Write-Host "Docker is already running"
} else {
    ##### Start Docker
    Start-Process -FilePath "C:\\Program Files\\Docker\\Docker\\Docker Desktop.exe" -ErrorAction Break 
    Write-Host "Docker is now starting..."
    Start-Sleep -Seconds 15
}

pwsh -c {
    "Switching operating mode to Linux from Windows container mode"
    cd "c:\program Files\Docker\Docker"                                                                                                                                                                                                                         
    .\DockerCli.exe -SwitchLinuxEngine
    sleep 15
    
}



### Git
if (-not (Get-Command "git" -ErrorAction SilentlyContinue)) {
    Write-Host "Git is not installed. Installing it now."
    Invoke-WebRequest -Uri https://git-scm.com/download/win -OutFile .\GitInstaller.exe
    Start-Process -Wait -FilePath .\GitInstaller.exe
    Remove-Item .\GitInstaller.exe
    Write-Host "Git installation completed. Continuing with the script."
} else {
    Write-Host "Git is already installed. Continuing with the script."
}



### AzCopy v10 installation
if (-not (Get-Command "azcopy" -ErrorAction SilentlyContinue)) {
    ## Ensure that you are running the script as an Administrator
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host "Please run this script as an Administrator to ensure we can update AzCopy env. path, if needed."
        break
    } else {
    Write-Host "You are running this script as an Administrator. Continuing with the script."
        }

    Write-Host "AzCopy v10 is not installed. Installing it now."
    mkdir $env:SystemDrive\AzCopy -ErrorAction SilentlyContinue
    Invoke-WebRequest -Uri https://aka.ms/downloadazcopy-v10-windows -OutFile $env:SystemDrive\AzCopy.zip
    Expand-Archive -Path $env:SystemDrive\AzCopy.zip -DestinationPath $env:SystemDrive\AzCopy
    $env:Path += ";$PWD\AzCopy"
    Remove-Item .\AzCopy.zip
    Write-Host "AzCopy v10 installation completed. Continuing with the script."
} else {
    Write-Host "AzCopy v10 is already installed. Returning to deployment script."
}

$env:AZCOPY_AUTO_LOGIN_TYPE = "AZCLI"