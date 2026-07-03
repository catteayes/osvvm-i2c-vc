#  File Name:         build.pro
#
#  Maintainer:        Mehmet Burak Aykenar    email: burak.aykenar@anadologic.com
#
#  Description:
#      Compile the OSVVM I2C verification components into library osvvm_i2c.
#      Requires OsvvmLibraries (osvvm + Common) to be built first.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      https://www.apache.org/licenses/LICENSE-2.0
#

library osvvm_i2c

analyze ./src/I2cTbPkg.vhd
analyze ./src/I2cComponentPkg.vhd
analyze ./src/I2cContext.vhd
analyze ./src/I2cController.vhd
analyze ./src/I2cPeripheral.vhd
