# Requires -Module Az.Compute, Az.Network, Az.Resources

param (
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory=$true)]
    [string]$Location,

    [Parameter(Mandatory=$true)]
    [string]$VmName,

    [Parameter(Mandatory=$true)]
    [string]$VmSize,

    [Parameter(Mandatory=$true)]
    [string]$AdminUsername,

    [Parameter(Mandatory=$true)]
    [string]$AdminPassword # Use a secure string for production
)

Write-Host "Connecting to Azure..."
# Ensure you are connected to Azure
try {
    Get-AzContext -ErrorAction Stop | Out-Null
}
catch {
    Write-Error "Not connected to Azure. Please run Connect-AzAccount first."
    exit 1
}

Write-Host "Checking if resource group '$ResourceGroupName' exists..."
$rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue

if (-not $rg) {
    Write-Host "Resource group '$ResourceGroupName' does not exist. Creating it now..."
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force | Out-Null
    Write-Host "Resource group '$ResourceGroupName' created successfully."
} else {
    Write-Host "Resource group '$ResourceGroupName' already exists."
}

$publicIpName = "$VmName-ip"
$nicName = "$VmName-nic"
$vnetName = "$ResourceGroupName-vnet"
$subnetName = "$ResourceGroupName-subnet"

# Check and create Virtual Network
Write-Host "Checking if Virtual Network '$vnetName' exists..."
$vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $vnetName -ErrorAction SilentlyContinue
if (-not $vnet) {
    Write-Host "Creating Virtual Network '$vnetName'..."
    $subnet = New-AzVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix "10.0.0.0/24"
    $vnet = New-AzVirtualNetwork -Name $vnetName -ResourceGroupName $ResourceGroupName -Location $Location -AddressPrefix "10.0.0.0/16" -Subnet $subnet
    Write-Host "Virtual Network '$vnetName' created."
} else {
    Write-Host "Virtual Network '$vnetName' already exists."
}

# Create Public IP Address
Write-Host "Creating Public IP address '$publicIpName'..."
$publicIp = New-AzPublicIpAddress -Name $publicIpName -ResourceGroupName $ResourceGroupName -Location $Location -AllocationMethod Static -Sku Basic
Write-Host "Public IP address '$publicIpName' created."

# Create Network Interface Card (NIC)
Write-Host "Creating Network Interface Card '$nicName'..."
$nic = New-AzNetworkInterface -Name $nicName -ResourceGroupName $ResourceGroupName -Location $Location -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $publicIp.Id
Write-Host "Network Interface Card '$nicName' created."

# Create a credential object
$cred = Get-Credential -UserName $AdminUsername -Message "Enter password for $AdminUsername"

# Configure the VM
Write-Host "Configuring VM '$VmName'..."
$vmConfig = New-AzVMConfig -VMName $VmName -VMSize $VmSize
$vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName $VmName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate
$vmConfig = Set-AzVMSourceImage -VM $vmConfig -Publisher "MicrosoftWindowsServer" -Product "WindowsServer" -Sku "2019-Datacenter" -Version "latest" # Example for Windows Server
# For Ubuntu, use:
# $vmConfig = Set-AzVMSourceImage -VM $vmConfig -Publisher "Canonical" -Product "UbuntuServer" -Sku "18.04-LTS" -Version "latest"
$vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $nic.Id

# Create the VM
Write-Host "Creating Virtual Machine '$VmName'..."
New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $vmConfig
Write-Host "Virtual Machine '$VmName' created successfully!"
