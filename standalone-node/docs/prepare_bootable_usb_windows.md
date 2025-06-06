# Preparing Bootable USB for Single Edge Node (Windows)

## Introduction

This document explains the procedure to create a bootable USB device for Standalone Edge Node installation.

## Prerequisites

- WSL Ubuntu-22.04 distribution installed on your system.

### Enable Windows Subsystem for Linux (WSL)

1. Navigate to "Programs and Features" in the Control Panel:

   Press `Win + R` to open the "Run" dialog, type `appwiz.cpl`, and hit Enter.
2. Click on "Turn Windows features on or off."
3. In the list of features, locate and select "Windows Subsystem for Linux."
4. Click OK to apply the changes.

### Install Ubuntu 22.04 on Windows Subsystem for Linux

1. Open PowerShell in administrator mode by right-clicking and selecting "Run as administrator".
2. List available Linux distributions with the following command:

   ```shell
   wsl --list --online
   ```
3. Select `Ubuntu-22.04` from the list and install it:

   ```shell
   wsl –install -d  Ubuntu-22.04
   ```
   During installation, you will be asked to provide a username and a password.
4. If prompted by PowerShell, reboot the system after the installation to apply the new changes.
5. Enable Network for WSL:

   Open PowerShell in administrator mode (if applicable) and run the following command:

   ```shell
   Get-NetAdapter | Where-Object Name -Like "*WSL*" | Enable-NetAdapter
   ```

## Prepare a USB Drive

### Step 1: Attach a USB Drive to Ubuntu

1. Install `usbipd` to share the USB drive with Ubuntu from Windows.

   Make sure to use PowerShell terminal with administrative privileges:

   ```shell
   winget install usbipd
   ```
   Restart the PowerShell terminal.
2. Get the bus number of the USB drive attached to the system:

   ```shell
   usbipd list
   ```
3. Bind the drive using the following command:

   ```shell
   usbipd bind --force --busid <busid for USB Drive>
   ```
4. Start Ubuntu by running the command in PowerShell:

   ```shell
   ubuntu2204.exe
   ```
   It will ask for the username and password you set previously. Upon successful login, the Ubuntu terminal will open.

5. Use PowerShell to attach the drive:

   ```shell
   usbipd attach --wsl --busid <busid for USB Drive>
   ```

   Now, the USB drive will be mounted in Ubuntu.
   You may need to restart Ubuntu to see the changes.

6. In the Ubuntu terminal, verify if the attached USB drive is listed:

   ```shell
   lsusb
   ```

### Step 2: Create a Bootable USB drive

Follow the [instructions to prepare a bootable USB drive](./user-guide/Get-Started-Guide.md#15--prepare-the-usb-drive).

### Step 3: Copy the ESH Package to Ubuntu

Use `cp -r` in the Ubuntu terminal to copy the ESH package from Windows to Linux.

> **NOTE**: By default, in WSL, the `/mnt/c` directory points to `C:\` in Windows.
