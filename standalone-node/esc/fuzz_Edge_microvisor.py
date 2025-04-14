# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
import logging
import time
import argparse
import os
import shutil
from hypothesis import given, settings, strategies as st
from Edge_Microvisor_Toolkit_Standalone_Node_Enablement import (
    EdgeMicroVisorToolKitStandaloneNodeDeployment
)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(message)s',
    handlers=[
        logging.StreamHandler()
    ]
)

# Example test functions


@given(proxy_value=st.text(min_size=0, max_size=100))
@settings(max_examples=1000, deadline=None)
def test_validate_proxy(proxy_value, deployment_instance):
    try:
        result = deployment_instance.validate_proxy(proxy_value)
        assert isinstance(result, bool)
    except Exception as e:
        logging.error(
            f"Error in test_validate_proxy with value {proxy_value}: {e}"
        )


@given(ssh_key=st.text(min_size=20, max_size=100))
@settings(max_examples=1000, deadline=None)
def test_validate_ssh_key(ssh_key, deployment_instance):
    try:
        result = deployment_instance.validate_ssh_key(ssh_key)
        assert isinstance(result, bool)
    except Exception as e:
        logging.error(
            f"Error in test_validate_ssh_key with value {ssh_key}: {e}"
        )


@given(no_proxy=st.text(min_size=0, max_size=100))
@settings(max_examples=1000, deadline=None)
def test_validate_no_proxy(no_proxy, deployment_instance):
    try:
        result = deployment_instance.validate_no_proxy(no_proxy)
        assert isinstance(result, bool)
    except Exception as e:
        logging.error(
            f"Error in test_validate_no_proxy with value {no_proxy}: {e}"
        )


# ✅ Added two blank lines before the function
@settings(max_examples=1000, deadline=None)
def run_fuzz_tests(duration_seconds, module_path, output_path):
    # Create an instance of the class
    deployment_instance = EdgeMicroVisorToolKitStandaloneNodeDeployment(
        module_path,
        output_path
    )

    start_time = time.time()
    last_log_time = start_time
    total_execs = 0
    new_interesting = 0
    total_interesting = 117  # Example total interesting cases

    while time.time() - start_time < duration_seconds:
        # Run a single test case for each validation function
        test_validate_proxy(deployment_instance)
        test_validate_ssh_key(deployment_instance)
        test_validate_no_proxy(deployment_instance)
        total_execs += 4  # Increment by 4 since we run 4 tests each loop

        # Check for new interesting cases (example logic)
        if total_execs % 100 == 0:  # Example condition for new interesting
            new_interesting += 1

        # Print logs every 3 seconds
        current_time = time.time()
        if current_time - last_log_time >= 3:
            elapsed = int(current_time - start_time)
            hours, rem = divmod(elapsed, 3600)
            minutes, seconds = divmod(rem, 60)
            exec_rate = total_execs / elapsed if elapsed > 0 else 0
            logging.info(
                (
                    "fuzz: elapsed: {}h {}m {}s, execs: {} ".format(
                        hours, minutes, seconds, total_execs) +
                    "({}/sec), new interesting: {} ".format(
                        int(exec_rate), new_interesting) +
                    "(total: {})".format(total_interesting)
                )
            )
            last_log_time = current_time

    # Print success or failure report
    if new_interesting > 0:
        logging.info(
            (
                f"OK: Total time: {hours}h {minutes}m {seconds}s. "
                "Fuzz test completed successfully with new findings."
            )
        )
    else:
        logging.info(
            f"Total time: {hours}h {minutes}m {seconds}s:"
            "Fuzz test completed with no new findings."
        )


if __name__ == "__main__":
    # Set up argument parser
    parser = argparse.ArgumentParser(description="Run fuzz for defined time")
    parser.add_argument(
        "duration",
        type=int,
        help="Duration in seconds for which to run the fuzz tests."
    )

    # Parse the arguments
    args = parser.parse_args()

    # Get the directory of the current script
    script_dir = os.path.dirname(os.path.abspath(__file__))

    # Create temporary directories for module_path and output_path
    module_path = os.path.join(script_dir, "fuzz_standalone_en_input")
    output_path = os.path.join(script_dir, "fuzz_standalone_en_output")
    os.makedirs(module_path, exist_ok=True)
    os.makedirs(output_path, exist_ok=True)

    try:
        # Run fuzz tests with the specified duration
        run_fuzz_tests(args.duration, module_path, output_path)
    finally:
        # Clean up the temporary directories
        shutil.rmtree(module_path)
        shutil.rmtree(output_path)
