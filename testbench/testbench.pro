#  File Name:         testbench.pro
#
#  Maintainer:        Mehmet Burak Aykenar    email: burak.aykenar@anadologic.com
#
#  Description:
#      Compile the I2C testbench and run all test cases.
#      Add one RunTest line per new TbI2c_*.vhd test case.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      https://www.apache.org/licenses/LICENSE-2.0
#

library osvvm_TbI2c

analyze TestCtrl_e.vhd
analyze TbI2c.vhd

RunTest TbI2c_WriteRead1.vhd
