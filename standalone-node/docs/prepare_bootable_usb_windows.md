# Preparing Bootable USB for Single Edge Node (Windows)

## Introduction

This document explains the procedure to create a bootable USB device for Standalone Edge Node installation.

## Pre-requisites

- PowerShell must be installed.
- Ensure that the Windows Subsystem for Linux (WSL) is enabled on your system.

### Steps to Enable WSL

1. Open the Control Panel on your Windows computer.
2. Navigate to Programs.
3. Click on "Turn Windows features on or off."
4. In the list of features, locate and select "Windows Subsystem for Linux."
5. Click OK to apply the changes.

## Procedure

### Step 1: Install Ubuntu 22.04 Linux Sub-system on Windows

1. Open a PowerShell prompt as an Administrator.
2. Run the command to list available distributions:
    ```shell
    wsl --list --online
3. Select Ubuntu 22.04 from the list and Install Ubuntu 22.04:
    ```shell
    wsl –install -d  Ubuntu-22.04
    ```
   During installation, it will ask for a username and password. Please provide valid credentials.
4. After Ubuntu installation completes, PowerShell may ask to reboot the system to apply the new changes.If prompted, please reboot the system once.

### Step 2: Enable Network for WSL

1. Open PowerShell in admin mode (if applicable) and run the following command to enable the network:
    ```shell
    Get-NetAdapter | Where-Object Name -Like "*WSL*" | Enable-NetAdapter

### Step 3: Start Ubuntu

1. Start Ubuntu by running the command in PowerShell:
    ```shell
    ubuntu2204.exe
    ```
   It will ask for the username and password you set previously. Upon successful login, you will see the Ubuntu terminal.

### Step 4: Attach USB Device to Ubuntu

1. Open another PowerShell terminal with Administrator privileges (if applicable).
2. Install usbipd to share the USB device with Ubuntu from Windows:
    ```shell
    winget install usbipd
    ```
    Restart the PowerShell terminal
3. Get the bus number of the USB device attached to the system:
    ```shell
    usbipd list
4. Bind the device using the following command:
    ```shell
    usbipd bind --force --busid <busid for USB Device>
5. Attach the USB to WSL Ubuntu. Use the following command and restart the machine before running this command:
    ```shell
    usbipd attach --wsl --busid <busid for USB Device>

### Step 5: USB Bootable Preparation

1. Now the USB will be listed on the Ubuntu terminal. You can start the USB bootable preparation as mentioned in the [Intel Wiki](https://wiki.ith.intel.com/pages/viewpage.action?pageId=3996554119#EdgeMicrovisorToolkitStandaloneNode-StandaloneEdgeNodeinstallationusingESCpackage).

### Step 6: Copy ESH Package to Ubuntu

1. Copy the ESH package from the Windows machine to the Ubuntu Linux machine using the following command:
    - By default,`/mnt/c` from the Linux terminal will take you to the Windows system. From there, navigate to the folder and use `cp -r` to copy to the Linux system.
