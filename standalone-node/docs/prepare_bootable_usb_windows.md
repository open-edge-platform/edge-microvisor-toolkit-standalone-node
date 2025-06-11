# Preparing Bootable USB for Single Edge Node (Windows)

## Introduction

This document explains the procedure to create a bootable USB device for Standalone Edge Node installation.

## Prerequisites

- WSL Ubuntu-22.04 distribution installed on your system.
- Alternatively, Ubuntu-22.04 Virtual Machine in Hyper-V

### Enable Windows Subsystem for Linux (WSL) or Hyper-V Manager

1. Navigate to "Programs and Features" in the Control Panel:

   Press `Win + R` to open the "Run" dialog, type `appwiz.cpl`, and hit Enter.
2. Click on "Turn Windows features on or off."
3. In the list of features, locate and select:
   - "Windows Subsystem for Linux", or
   - "Hyper-V".
4. Click OK to apply the changes.

> **NOTE**: A reboot may be required to apply changes to the operating system.

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

### Install Ubuntu 22.04 in a Hyper-V Virtual Machine

1. Download the .ISO image for Ubuntu 22.04.5 LTS (Jammy Jellyfish).
2. Start Hyper-V Manager and select *Action-> New-> Virtual Machine*.
3. Provide a name for your VM and press *Next*.
4. Select *Generation 2 (VHDX)*, then press *Next*.
5. Set the desired amount of memory to allocate, then press *Next*.
6. Select a virtual network switch, then press *Next*.
7. Select *Create a virtual hard disk* and one of two options:

   - Select a location for your VHDX and set your desired disk size, then press *Next*.
   - Select *Install an operating system from a bootable image file* and browse to the
      .ISO image.
   - Press *Finish*.

8. Right click your virtual machine from Hyper-V Manager. Select *Settings...*
9. Select *Security* and enable *Secure Boot*. Choose the *Microsoft UEFFI Certificate Authority*
   template.
10. Select *Firmware* and adjust the boot order so *DVD Drive* is the first and *Hard Drive*
    is second.
11. Select *Integration services* under *Management* and check *Guest Services*.
12. Click *Apply* to apply all changes.
13. Right click your VM and select *Connect...*. Select *Start*.
14. Follow the installer prompts to install Ubuntu. Then, *Restart* to reboot the machine.
    The installation ISO will be automatically ejected.


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
4. Start Ubuntu:

   a. (WSL) Run the command in PowerShell:

      ```shell
      ubuntu2204.exe
      ```
      It will ask for the username and password you set previously. Upon successful login,
      the Ubuntu terminal will open.

   b. (Hyper-V) Run Hyper-V Manager, right click your VM, and select *Connect...*.
      Select *Start*.


5. Attach the drive:

   a. (WSL) Use PowerShell and run the command:

      ```shell
      usbipd attach --wsl --busid <busid for USB Drive>
      ```

   b. (Hyper-V) Start the Ubuntu terminal:


      - Install Usbip tools:

        ```bash
        sudo apt install linux-tools-virtual hwdata
        sudo update-alternatives --install /usr/local/bin/usbip usbip `ls /usr/lib/linux-tools/*/usbip | tail -n1` 20
        sudo modprobe vhci-hcd
        ```

      - Run the following command:

        ```bash
        usbip attach --remote=<IPv4 address of host> --busid=<busid for USB Drive>
        ```

   **Now, the USB drive will be mounted in Ubuntu.**

   > **Note**:
   >
   > * If the system reboots, the USB device attachment is lost. You can either
   >   re-attach it after Ubuntu has restarted, or configure the OS to
   >   [automatically re-attach the device](https://wiki.archlinux.org/title/USB/IP#Binding_with_systemd_service).
   > * To quickly obtain the IPv4 address of your host machine, start *Command Prompt*,
   >   and run the following command:
   >
   >   ```shell
   >   ping <name-of-your-computer> -4
   >   ```


6. In the Ubuntu terminal, verify if the attached USB drive is listed:

   ```bash
   lsusb
   ```

### Step 2: Create a Bootable USB drive

Follow the [instructions to prepare a bootable USB drive](./user-guide/Get-Started-Guide.md#15--prepare-the-usb-drive).
