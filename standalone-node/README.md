#Pre-conditions for build env
Make sure docker installed and all required settings (to resolve proxies) must be done.
NOTE: Ubuntu 22.04 is prefeed OS for build setup.

# Create the Standalone Installation tar file with all required files for preparing bootable USB device
# run below command and it will build hook os and generate the sen-installation-files.tar.gz file
# sen-installation-files.tar.gz will be present under $(pwd)/installation scripts/out directory
make build

# Copy sen-installation-files.tar.gz  to Linux system to prepare the bootable USB
tar -xzf sen-installation-files.tar.gz
|
|------ usb-bootable-files.tar.gz
|------ proxy_ssh_config 
|
# Prepare the bootable USB device for OS installation on Edge node
bootable-usb-prepare.sh is to
   i) Generate the bootable USB device for booting the hook OS on RAM and install OS on the edge node.
   ii) Please provide valid inputs for the scripts such as
       usb -> valid usb device with name ex. /dev/sda
       usb-bootable-files.tar.gz  
       proxy_ssh_config -> this is to configure proxy settings if the edge node behind the firewall
                           ssh_key  is your Linux device id_ras.pub key ( from where you want to do remote ssh) for password less ssh connection with Edge node.

        NOTE: It's not mandatory to provide proxy's  provided if your Edge node not required such proxy settings to access internet services from outside.
             

    ex: sudo ./bootable-usb-prepare.sh /dev/sda usb-bootable-files.tar.gz proxy_ssh_config

   iii) Once script creates the bootable USB device it ready for installation.

# Login to Edge node after Successful installation
login details:
 -username: "user"
 -password: "user"
