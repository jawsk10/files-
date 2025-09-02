# Check administrator privileges
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Start-Process powershell "-File `"$PSCommandPath`"" -Verb RunAs
    exit
}

function Console
{
    param ([Switch]$Show,[Switch]$Hide)
    if (-not ("Console.Window" -as [type])) { 

        Add-Type -Name Window -Namespace Console -MemberDefinition '
        [DllImport("Kernel32.dll")]
        public static extern IntPtr GetConsoleWindow();

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
        '
    }

    if ($Show)
    {
        $consolePtr = [Console.Window]::GetConsoleWindow()

        $null = [Console.Window]::ShowWindow($consolePtr, 5)
    }

    if ($Hide)
    {
        $consolePtr = [Console.Window]::GetConsoleWindow()
        #0 hide
        $null = [Console.Window]::ShowWindow($consolePtr, 0)
    }
}

$global:keyboardKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\kbdclass\Parameters"
$global:mouseKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\mouclass\Parameters"

function Get-Buffer {
    $bufferSz = [PSCustomObject]@{
        KeyboardBufferSize = $null
        MouseBufferSize = $null
    }

    # Verificación de la existencia de la ruta del registro del teclado
    if (Test-Path -Path $keyboardKeyPath) {
        try {
            $bufferSz.KeyboardBufferSize = Get-ItemPropertyValue -Path $keyboardKeyPath -Name "KeyboardDataQueueSize"
        } catch {
            $bufferSz.KeyboardBufferSize = "100"
        }
    } else {
        $bufferSz.KeyboardBufferSize = "100"
    }

    # Verificación de la existencia de la ruta del registro del ratón
    if (Test-Path -Path $mouseKeyPath) {
        try {
            $bufferSz.MouseBufferSize = Get-ItemPropertyValue -Path $mouseKeyPath -Name "MouseDataQueueSize"
        } catch {
            $bufferSz.MouseBufferSize = "100"
        }
    } else {
        $bufferSz.MouseBufferSize = "100"
    }

    return $bufferSz
}


function Set-Buffer {
    param (
        [Parameter(Mandatory = $true)]
        [int]$keyboardBufferSize,

        [Parameter(Mandatory = $true)]
        [int]$mouseBufferSize
    )

    # Verificación y creación de la clave del teclado si no existe
    if (-not (Test-Path -Path $keyboardKeyPath)) {
        New-Item -Path $keyboardKeyPath -Force | Out-Null
    }

    # Verificación y creación de la clave del ratón si no existe
    if (-not (Test-Path -Path $mouseKeyPath)) {
        New-Item -Path $mouseKeyPath -Force | Out-Null
    }

    Set-ItemProperty -Path $mouseKeyPath -Name "MouseDataQueueSize" -Value $mouseBufferSize
    Set-ItemProperty -Path $keyboardKeyPath -Name "KeyboardDataQueueSize" -Value $keyboardBufferSize

    # Mostrar advertencia si los valores son demasiado pequeños
    if ($keyboardBufferSize -lt 10 -or $mouseBufferSize -lt 10) {
        [System.Windows.Forms.MessageBox]::Show("Setting a value too small could cause buffer overflow", "Info", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
}


function Update-Buffer {
    $bufferSz = Get-Buffer
    $textBoxKbdClass.Text = $bufferSz.KeyboardBufferSize
    $textBoxMouClass.Text = $bufferSz.MouseBufferSize
}

Console -Hide
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Crear la ventana principal
[System.Windows.Forms.Application]::EnableVisualStyles()
$form = New-Object System.Windows.Forms.Form
$form.ClientSize = New-Object System.Drawing.Size(245, 85)
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.Text = "Set-Input-Buffer"
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$form.KeyPreview = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(44, 44, 44)
$form.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F5) {
        Update-Buffer
    }
})

# Obtener los buffer actuales
$bufferSz = Get-Buffer

# Mouclass
$labelMouClass = New-Object System.Windows.Forms.Label
$labelMouClass.Size = New-Object System.Drawing.Size(100, 15)
$labelMouClass.Location = New-Object System.Drawing.Point(20, 10)
$labelMouClass.Text = "MouClassBufferSz"
$labelMouClass.ForeColor = [System.Drawing.Color]::White
$labelMouClass.BackColor = [System.Drawing.Color]::Transparent
$form.Controls.Add($labelMouClass)

$textBoxMouClass = New-Object System.Windows.Forms.TextBox
$textBoxMouClass.Location = New-Object System.Drawing.Point(40, 30)
$textBoxMouClass.Size = New-Object System.Drawing.Size(55, 30)
$textBoxMouClass.Text = $bufferSz.MouseBufferSize
$textBoxMouClass.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$textBoxMouClass.BackColor = [System.Drawing.Color]::FromArgb(66, 66, 66)
$textBoxMouClass.ForeColor = [System.Drawing.Color]::White
$textBoxMouClass.MaxLength = 4
$form.Controls.Add($textBoxMouClass)

# KbdClass
$labelKbdClass = New-Object System.Windows.Forms.Label
$labelKbdClass.Size = New-Object System.Drawing.Size(100, 15)
$labelKbdClass.Location = New-Object System.Drawing.Point(130, 10)
$labelKbdClass.Text = "KbdClassBufferSz"
$labelKbdClass.ForeColor = [System.Drawing.Color]::White
$labelKbdClass.BackColor = [System.Drawing.Color]::Transparent
$form.Controls.Add($labelKbdClass)

$textBoxKbdClass = New-Object System.Windows.Forms.TextBox
$textBoxKbdClass.Location = New-Object System.Drawing.Point(150, 30)
$textBoxKbdClass.Size = New-Object System.Drawing.Size(55, 30)
$textBoxKbdClass.Text = $bufferSz.KeyboardBufferSize
$textBoxKbdClass.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$textBoxKbdClass.BackColor = [System.Drawing.Color]::FromArgb(66, 66, 66)
$textBoxKbdClass.ForeColor = [System.Drawing.Color]::White
$textBoxKbdClass.MaxLength = 4
$form.Controls.Add($textBoxKbdClass)

# KeyPress event handlers
function OnKeyPress {
    param (
        [System.Object]$sender, 
        [System.Windows.Forms.KeyPressEventArgs]$e
    )
    if ($e.KeyChar -notmatch '[0-9]' -and $e.KeyChar -ne [char][System.Windows.Forms.Keys]::Back) {
        $e.Handled = $true
    }
}


$textBoxKbdClass.Add_KeyPress({ OnKeyPress -sender $textBoxKbdClass -e $_ })
$textBoxMouClass.Add_KeyPress({ OnKeyPress -sender $textBoxMouClass -e $_ })

# Save
$saveButton = New-Object System.Windows.Forms.Button
$saveButton.Location = New-Object System.Drawing.Point(97, 60)
$saveButton.Size = New-Object System.Drawing.Size(50, 20)
$saveButton.Text = "Save"
$saveButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$saveButton.BackColor = [System.Drawing.Color]::FromArgb(66, 66, 66)
$saveButton.ForeColor = [System.Drawing.Color]::White
$saveButton.FlatAppearance.BorderSize = 0
$saveButton.Add_Click({
    $MouClassBuff = $textBoxMouClass.Text
    $KbdClassBuff = $textBoxKbdClass.Text
    if ($MouClassBuff -and $KbdClassBuff) {
        Set-Buffer -keyboardBufferSize $KbdClassBuff -mouseBufferSize $MouClassBuff
        Update-Buffer
    } else {
        [System.Windows.Forms.MessageBox]::Show("Please provide correct buffer", "Info", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
})
$form.Controls.Add($saveButton)

# Reset
$ResetButton = New-Object System.Windows.Forms.Button
$ResetButton.Location = New-Object System.Drawing.Point(220, 63)
$ResetButton.Size = New-Object System.Drawing.Size(20, 17)
$ResetButton.Text = "↻"
$ResetButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$ResetButton.BackColor = [System.Drawing.Color]::FromArgb(66, 66, 66)
$ResetButton.ForeColor = [System.Drawing.Color]::White
$ResetButton.FlatAppearance.BorderSize = 0
$ResetButton.Add_Click({
    if (Test-Path -Path $keyboardKeyPath) {
        Remove-ItemProperty -Path $keyboardKeyPath -Name "KeyboardDataQueueSize" -Force | Out-Null
    }

    if (Test-Path -Path $mouseKeyPath) {
        Remove-ItemProperty -Path $mouseKeyPath -Name "MouseDataQueueSize" -Force | Out-Null
    }

    Update-Buffer
})
$form.Controls.Add($ResetButton)

$form.ShowDialog()