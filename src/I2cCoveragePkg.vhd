--
--  File Name:         I2cCoveragePkg.vhd
--  Design Unit Name:  I2cCoveragePkg
--
--  Maintainer:        Mehmet Burak Aykenar    email: burak.aykenar@anadologic.com
--  Contributor(s):
--     <intern name>
--
--  Description:
--      Shared support for the I2C functional coverage models (#18):
--      address ranges, transfer lengths, read/write x repeated-START
--      crosses, error cases, speed classes. Each test declares its own
--      local coverage signals and defines its own bins inline.
--
--  Revision History:
--    Date      Version    Description
--    08/2026   0.1        Initial functional coverage support (#18)
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

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library std;
    use std.textio.all;

library osvvm;
    context osvvm.OsvvmContext;

package I2cCoveragePkg is

    type I2cErrorKindType is (
        ERR_NONE,
        ERR_NACK
    );

    function I2cAddrRangeBucket(Addr : std_logic_vector; AddrWidth : integer) return integer;

    -- Shared coverage database file names for every test
    constant ADDR_COV_DB_FILE  : string := "I2cCoverage_Addr.txt";
    constant XFER_COV_DB_FILE  : string := "I2cCoverage_Xfer.txt";
    constant RWSR_COV_DB_FILE  : string := "I2cCoverage_RwSr.txt";
    constant ERROR_COV_DB_FILE : string := "I2cCoverage_Error.txt";
    constant SPEED_COV_DB_FILE : string := "I2cCoverage_Speed.txt";

    -- Merge in a previously saved database if one exists.
    procedure MergeCovDbIfExists(ID : CoverageIDType; FileName : string);

end package I2cCoveragePkg;

package body I2cCoveragePkg is

    function I2cAddrRangeBucket(Addr : std_logic_vector; AddrWidth : integer) return integer is
        variable AddrInt : integer;
    begin
        AddrInt := to_integer(unsigned(Addr));
        if AddrWidth > 7 then
            if    AddrInt <  256 then return 0; -- Addr(9:8) = "00"
            elsif AddrInt <  512 then return 1; -- Addr(9:8) = "01"
            elsif AddrInt <  768 then return 2; -- Addr(9:8) = "10"
            else                      return 3; -- Addr(9:8) = "11"
            end if;
        else
            if    AddrInt <    8 then return 0;  -- reserved (0000 XXX)
            elsif AddrInt <  120 then return 1;  -- normal address
            else                      return 2;  -- reserved (1111 XXX)
            end if;
        end if;
    end function I2cAddrRangeBucket;

    procedure MergeCovDbIfExists(ID : CoverageIDType; FileName : string) is
        file     CovDbFile  : text;
        variable OpenStatus : file_open_status;
    begin
        file_open(OpenStatus, CovDbFile, FileName, READ_MODE);
        if OpenStatus = OPEN_OK then
            file_close(CovDbFile);
            ReadCovDb(ID, FileName, Merge => true);
        end if;
    end procedure MergeCovDbIfExists;

end package body I2cCoveragePkg;
