--
--  File Name:         I2cContext.vhd
--  Design Unit Name:  I2cContext
--
--  Maintainer:        Mehmet Burak Aykenar    email: burak.aykenar@anadologic.com
--  Contributor(s):
--     <intern name>
--
--  Description:
--      Context declaration for the I2C verification component packages.
--
--  Revision History:
--    Date      Version    Description
--    07/2026   0.1        Initial skeleton
--
--  Licensed under the Apache License, Version 2.0 (the "License");
--  you may not use this file except in compliance with the License.
--  You may obtain a copy of the License at
--
--      https://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software
--  distributed under the License is distributed on an "AS IS" BASIS,
--  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--  See the License for the specific language governing permissions and
--  limitations under the License.
--

context I2cContext is
    library osvvm_common;
        context osvvm_common.OsvvmCommonContext;

    library osvvm_i2c;
        use osvvm_i2c.I2cTbPkg.all;
        use osvvm_i2c.I2cComponentPkg.all;
end context I2cContext;
