# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
"""
# Edge Microvisor Toolkit Standalone Node Enablement CLI Deployment
"""
import os
import re
from subprocess import run, PIPE
from termcolor import colored
from esb_common.logger import Logger
from esb_common import locale
import sys
import tty
import termios

MODULE = "Edge Microvisor Toolkit Standalone Node Script"
CURRENT_DIR = os.getcwd()
LOG_DIR = os.path.join(CURRENT_DIR, "log")
HOME_DIR = os.environ.get("HOME")
ESH_REQUIRED = "yes"


class EdgeMicroVisorStandaloneNodeDeploymentException(Exception):
    """
    Exception handling class
    """
    pass


class EdgeMicroVisorToolKitStandaloneNodeDeployment(object):
    """
    Main class for the module package
    """

    def __init__(self, module_path, output_path):
        self.module = MODULE
        self.output_path = output_path
        self.module_path = module_path
        log_file = "{0}/install.log".format(self.output_path)
        if not os.path.isdir(self.output_path):
            os.mkdir(self.output_path)
        self.log = Logger(log_file)
        self.pbar = None
        self.str_len = 50
        self.log.info("Version - 1.0")
        self.install_marker_file = (
            f"{CURRENT_DIR}/installation_completion.marker"
        )

    def main_install(self):
        """
        Method for build host package
        :return: None
        """
        self.log.info("{0} {1}".format(locale.MAIN_START, self.module))
        try:
            self.install_standalone_edge_node_setup_script()
        except Exception as exp:
            raise Exception(
                "Failed to enable Edge Microvisor Toolkit Standalone Node: %s"
                % str(exp)
            )
        self.log.info("{0} {1}".format(locale.MAIN_COMPLETE, self.module))

    def install(self):
        """
        Method to call main_install and main_post_install
        :return: status :type: bool
        """
        # Start installation
        status = True
        try:
            self.main_install()
            self.main_post_install()
        except EdgeMicroVisorStandaloneNodeDeploymentException as error:
            if error.args[0]:
                if isinstance(error.args[0], bytes):
                    self.log.error(error.args[0].decode('utf-8'))
                else:
                    self.log.error(error.args[0])
            if error.args[1]:
                self.log.error(error.args[1])
                print("{0} {1}".format(
                    colored("ERROR:", "red"), error.args[1]))
            if error.args[2]:
                self.log.debug(error.args[2])
                print("{0} {1}".format(
                    colored("Failed command :", "red"), error.args[2]
                ))
            status = False
        except KeyboardInterrupt:
            print("{0} {1}".format(
                colored("WARNING:", "yellow"), locale.USER_ABORTED))
            self.log.warn(locale.USER_ABORTED)
            status = False
        except Exception as err:
            print("{0} {1}".format(colored("ERROR:", "red"), err))
            self.log.error(err)
            status = False
        finally:
            self.cleanup()
            os.chdir(CURRENT_DIR)

        if status:
            self.log.info("Successfully installed {0}".format(self.module))
        else:
            self.log.error("Installation failed for {0}".format(self.module))
        return status

    # Define a function to validate the proxy format using regex
    def validate_proxy(self, proxy_value):
        proxy_regex = re.compile(
            r'^(http://|https://)'
            r'([A-Za-z0-9.-]+\.[A-Za-z]{2,}|localhost)'
            r'(:[0-9]{1,5})?$'
        )
        return bool(proxy_regex.match(proxy_value))

    def validate_ssh_key(self, ssh_key):
        if not ssh_key:  # Allow empty SSH keys
            return True
        ssh_key_regex = re.compile(
            r'^(ssh-(rsa|ed25519)) ([A-Za-z0-9+/=]+) ?(.*)$'
        )
        return bool(ssh_key_regex.match(ssh_key))

    def validate_no_proxy(self, no_proxy):
        if not no_proxy:
            return True
        no_proxy_regex = re.compile(r'^[^,\s]+(,[^,\s]+)*$')
        return bool(no_proxy_regex.match(no_proxy))

    def update_proxy_file(self, http_proxy, https_proxy, no_proxy, ssh_key,
                          user_name, password, file_path):
        try:
            with open(file_path, 'w') as file:
                file.write(f'http_proxy="{http_proxy}"\n')
                file.write(f'https_proxy="{https_proxy}"\n')
                file.write(f'no_proxy="{no_proxy}"\n')
                file.write(f'HTTP_PROXY="{http_proxy}"\n')
                file.write(f'HTTPS_PROXY="{https_proxy}"\n')
                file.write(f'NO_PROXY="{no_proxy}"\n')
                file.write(f'ssh_key="{ssh_key}"\n')
                file.write(f'user_name="{user_name}"\n')
                file.write(f'passwd="{password}"\n')
            # Overwrite the password variable and delete it
            password = None
            del password
        except FileNotFoundError:
            self.log.error("Configuration file not found.")

    def run_lsblk(self):
        try:
            # Run the lsblk command with filtering for disks
            command = ["lsblk", "-o", "NAME,SIZE,TYPE,MODEL"]
            result = run(command, stdout=PIPE,
                         stderr=PIPE, text=True, shell=False)
            if result.returncode == 0:
                # Filter output for disks
                disks = [line for line in result.stdout.splitlines()
                         if "disk" in line]
                return "\n".join(disks)
            else:
                print(colored("Error running lsblk:", "red"))
                self.log.error(result.stderr)
                return None
        except Exception as e:
            print(f"Error: {e}")
            self.log.error(f"Exception occurred: {e}")
            return None

    def install_standalone_edge_node_setup_script(self):
        """
        Starts the standalone EN script installation

        :return: None
        """
        self.log.info("----------------------------------------")
        self.log.info(
            "{0} Edge Microvisor Toolkit Standalone Node Enablement"
            .format(locale.INSTALL_STARTED))
        self.log.info("----------------------------------------")

        if not os.path.exists(LOG_DIR):
            os.mkdir(LOG_DIR)

        print("-------+----+-- Installation Begins --+----+-------")
        self.log.info("Installation begins.")

        # Search for sen-installation-files.tar.gz
        sen_file_path = None
        for dirpath, dirnames, filenames in os.walk(CURRENT_DIR):
            for filename in filenames:
                if filename == "sen-installation-files.tar.gz":
                    sen_file_path = os.path.join(dirpath, filename)
            if sen_file_path:
                break

        if not sen_file_path:
            self.log.error("File sen-installation-files.tar.gz not found.")
            print(colored(
                "ERROR: File sen-installation-files.tar.gz not found.",
                "red"))
            raise EdgeMicroVisorStandaloneNodeDeploymentException(
                "File sen-installation-files.tar.gz not found"
            )

        command = "tar -xvf {0}".format(sen_file_path)
        status = run(
            command.split(), stdout=PIPE, stderr=PIPE, shell=False)
        if status.returncode:
            self.log.error("Error during tar extraction.")
            self.log.error(
                f"Standard Output: {status.stdout.decode('utf-8')}"
            )
            self.log.error(
                f"Standard Error: {status.stderr.decode('utf-8')}"
            )
            raise EdgeMicroVisorStandaloneNodeDeploymentException(
                status.stdout + status.stderr,
                "{0} to unzip".format(locale.FAILED),
                command
            )

        files_to_check = [
            'config-file',
            'bootable-usb-prepare.sh',
            'usb-bootable-files.tar.gz',
            'edgenode-logs-collection.sh'
            ]

        # Get the list of files in the current directory
        current_directory_files = os.listdir(CURRENT_DIR)

        # Check for the presence of required file
        for file_name in files_to_check:
            if file_name in current_directory_files:
                self.log.info(f"{file_name} is present in directory.")
            else:
                raise EdgeMicroVisorStandaloneNodeDeploymentException(
                    f"{file_name} is not present.")

        # Get user inputs for the proxies, ssh key, user name and password
        http_proxy = input(colored(
            'Enter the HTTP proxy (leave blank for none): ', "green"))
        if http_proxy and not self.validate_proxy(http_proxy):
            self.log.error("Invalid HTTP proxy format. Exiting...")
            print(colored('Invalid HTTP proxy format. Exiting...', "red"))
            raise EdgeMicroVisorStandaloneNodeDeploymentException(
                "Invalid HTTP proxy format.")

        https_proxy = input(colored(
            'Enter the HTTPS proxy (leave blank for none): ', "green"))
        if https_proxy and not self.validate_proxy(https_proxy):
            self.log.error("Invalid HTTPS proxy format. Exiting...")
            print(colored('Invalid HTTPS proxy format. Exiting...', "red"))
            raise EdgeMicroVisorStandaloneNodeDeploymentException(
                "Invalid HTTPS proxy format.")

        no_proxy = input(colored(
            'Enter the NO_PROXY list (comma-separated): ',
            "green"))
        if not self.validate_no_proxy(no_proxy):
            self.log.error("Invalid NO_PROXY format. Exiting...")
            print(colored('Invalid NO_PROXY format. Exiting...', "red"))
            raise EdgeMicroVisorStandaloneNodeDeploymentException(
                "Invalid NO_PROXY format.")

        ssh_key = input(colored('Enter your SSH public key: ', "green"))
        if not self.validate_ssh_key(ssh_key):
            self.log.error("Invalid SSH key format. Exiting...")
            print(colored('Invalid SSH key format. Exiting...', "red"))
            raise EdgeMicroVisorStandaloneNodeDeploymentException(
                "Invalid SSH key format.")

        user_name = input(colored('Enter user name: ', "green"))
        password = masked_input(colored('Enter password: ', "green"))
        if not user_name or not password:
            raise EdgeMicroVisorStandaloneNodeDeploymentException(
                "User name or password cannot be empty.")

        proxy_ssh_config_path = os.path.join(
            CURRENT_DIR, "config-file"
        )
        self.update_proxy_file(
            http_proxy, https_proxy, no_proxy, ssh_key,
            user_name, password, proxy_ssh_config_path
        )
        print(colored(
            'proxy_ssh_config File updated successfully!', "green"))

        lsblk_output = self.run_lsblk()
        if lsblk_output:
            print(colored("Disk Information:\n", "green"))
            print(lsblk_output)

        disk = input(colored(
            "Enter the disk (e.g., /dev/sda, /dev/sdb): ",
            "green").strip()
            )
        print(colored(f"You selected the disk: {disk}", "green"))

        print(colored(
            "Starting bootable USB preparation, This process will take "
            "approximately 10 minutes...", "green"))

        command = [
            "sudo", "./bootable-usb-prepare.sh", disk,
            "usb-bootable-files.tar.gz", "config-file"
        ]

        process = run(command)
        if process.returncode == 0:
            print(colored(
                "Bootable USB preparation completed successfully!", "green"
            ))
            self.log.info(
                "Bootable USB preparation completed successfully."
            )
        else:
            self.log.error("Error during bootable USB preparation")
            print(colored(
                "Error during bootable USB preparation. "
                "See logs for details.", "red"
            ))
            raise EdgeMicroVisorStandaloneNodeDeploymentException(
                "Bootable USB preparation failed."
            )

    def verify_installation(self):
        """
        Verifies the mender update status
        :return: None
        """
        self.log.info("Verifying the installation...")
        self.verify_post_install()

    def cleanup(self):
        """
        Removes temporary files
        :return: None
        """
        pass

    def main_post_install(self):
        """
        This method post host package build
        :return: None
        """
        # Post installation verification

        self.log.info("{0} {1}".format(locale.POST_INSTALL_START, self.module))
        self.verify_installation()
        self.log.info("{0} {1}".format(
            locale.POST_INSTALL_COMPLETE, self.module
        ))

    def verify_post_install(self):
        """
        This method verifies the installation
        :return: None
        """
        pass

    def main_uninstall(self):
        """
        Method to uninstall the package
        :return: None
        """
        self.log.info("Successfully {0} {1}".format(
            locale.UNINSTALLED, self.module))
        return True


def main_install(MODULE_PATH, OUTPUT_PATH):
    en_script_install = EdgeMicroVisorToolKitStandaloneNodeDeployment(
        MODULE_PATH, OUTPUT_PATH
    )
    try:
        status = en_script_install.install()
    except Exception as e:
        en_script_install.log.error(e)
        en_script_install.log.clean()
        raise e
    en_script_install.log.clean()
    return status


def verify_install(MODULE_PATH, OUTPUT_PATH):
    en_script_install = EdgeMicroVisorToolKitStandaloneNodeDeployment(
        MODULE_PATH, OUTPUT_PATH
    )
    try:
        status = en_script_install.verify_post_install()
    except Exception as e:
        en_script_install.log.error(e)
        status = False
        en_script_install.log.clean()
        os.chdir(CURRENT_DIR)
    return status


def main_uninstall(MODULE_PATH, OUTPUT_PATH, TYPE):
    en_script_uninstall = EdgeMicroVisorToolKitStandaloneNodeDeployment(
        MODULE_PATH, OUTPUT_PATH
    )
    status = en_script_uninstall.main_uninstall()
    en_script_uninstall.log.clean()
    if status:
        return en_script_uninstall.SUCCESS
    else:
        return en_script_uninstall.FAILED


def masked_input(prompt):
    # Print the prompt
    sys.stdout.write(prompt)
    sys.stdout.flush()
    password = []
    old_settings = termios.tcgetattr(sys.stdin)
    tty.setraw(sys.stdin)

    try:
        while True:
            ch = sys.stdin.read(1)
            if ch == '\r' or ch == '\n':
                break
            elif ch in ('\x08', '\x7f'):
                if password:
                    password.pop()
                    sys.stdout.write('\b \b')
                    sys.stdout.flush()
            else:
                password.append(ch)
                sys.stdout.write('*')
                sys.stdout.flush()
    finally:
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_settings)
        sys.stdout.write('\n')

    # Overwrite password elements in memory
    password_str = ''.join(password)
    for i in range(len(password)):
        password[i] = '\0'
    del password

    return password_str
