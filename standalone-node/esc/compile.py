# SPDX-FileCopyrightText: (C) 2025 Intel Corporation
# SPDX-License-Identifier: Apache-2.0
from distutils.core import setup
from distutils.extension import Extension
from Cython.Distutils import build_ext

ext_modules = [
    Extension(
        "esb_install",
        ["Edge_Microvisor_Toolkit_Standalone_Node_Enablement.py"]
    ),
]

setup(
    name='Edge_Microvisor_Toolkit_Standalone_Node_Enablement',
    cmdclass={'build_ext': build_ext},
    ext_modules=ext_modules
)
