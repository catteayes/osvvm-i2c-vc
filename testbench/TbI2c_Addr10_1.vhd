--
--  File Name:         TbI2c_Addr10_1.vhd
--  Design Unit Name:  architecture Addr10_1 of TestCtrl
--
--  Maintainer:        Mehmet Burak Aykenar    email: burak.aykenar@anadologic.com
--  Contributor(s):
--     <intern name>
--
--  Description:
--      10-bit addressing test.
--
--  Revision History:
--    Date      Version    Description
--    08/2026   0.2        Functional coverage (#18)
--    08/2026   0.1        Initial 10-bit addressing test (#15)
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

architecture Addr10_1 of TestCtrl is

    signal TestDone : integer_barrier := 1;

    constant DEV_ADDR : std_logic_vector(9 downto 0) := "1111000001";
    constant WDATA    : std_logic_vector(7 downto 0) := X"65";
    constant RDATA    : std_logic_vector(7 downto 0) := X"34";

    signal AddrCov  : CoverageIDType;
    signal XferCov  : CoverageIDType;
    signal RwSrCov  : CoverageIDType;
    signal ErrorCov : CoverageIDType;
    signal SpeedCov : CoverageIDType;

begin

    ------------------------------------------------------------
    -- Test global control
    ------------------------------------------------------------
    ControlProc : process
    begin
        SetTestName("TbI2c_Addr10_1");
        SetLogEnable(PASSED, TRUE);
        SetLogEnable(DEBUG, TRUE);

        wait for 0 ns;  wait for 0 ns;
        TranscriptOpen;
        SetTranscriptMirror(TRUE);

        AddrCov  <= NewID("I2cAddressCoverage");
        XferCov  <= NewID("I2cTransferLengthCoverage");
        RwSrCov  <= NewID("I2cReadWriteRepeatedStartCoverage");
        ErrorCov <= NewID("I2cErrorCoverage");
        SpeedCov <= NewID("I2cSpeedClassCoverage");
        wait for 0 ns;  -- let the coverage IDs update

        AddCross(AddrCov, "AddrWidth x SubRange", GenBin(0, 1), GenBin(0, 3));

        -- Transfer length: single byte, then burst lengths 2/3/4+.
        AddBins(XferCov, "Single byte",   GenBin(1));
        AddBins(XferCov, "2-byte burst",  GenBin(2));
        AddBins(XferCov, "3-byte burst",  GenBin(3));
        AddBins(XferCov, "4+ byte burst", GenBin(4, 255, 1));

        -- Read/Write x repeated-START cross.
        AddCross(RwSrCov, "R/W x Sr", GenBin(0, 1), GenBin(0, 1));

        -- One bin per error-injection scenario.
        AddBins(ErrorCov, "NONE", GenBin(I2cErrorKindType'pos(ERR_NONE)));
        AddBins(ErrorCov, "NACK", GenBin(I2cErrorKindType'pos(ERR_NACK)));

        -- Speed classes: Standard/Fast/Fast+ (I2C_SCL_PERIOD_100K/400K/1M).
        AddBins(SpeedCov, "Standard (100K)", GenBin(1));
        AddBins(SpeedCov, "Fast (400K)",     GenBin(2));
        AddBins(SpeedCov, "Fast+ (1M)",      GenBin(3));

        MergeCovDbIfExists(AddrCov,  ADDR_COV_DB_FILE);
        MergeCovDbIfExists(XferCov,  XFER_COV_DB_FILE);
        MergeCovDbIfExists(RwSrCov,  RWSR_COV_DB_FILE);
        MergeCovDbIfExists(ErrorCov, ERROR_COV_DB_FILE);
        MergeCovDbIfExists(SpeedCov, SPEED_COV_DB_FILE);

        wait until n_Reset = '1';
        ClearAlerts;

        WaitForBarrier(TestDone, 10 ms);
        AlertIf(now >= 10 ms, "Test finished due to timeout");

        WriteCovDb(AddrCov,  ADDR_COV_DB_FILE);
        WriteCovDb(XferCov,  XFER_COV_DB_FILE);
        WriteCovDb(RwSrCov,  RWSR_COV_DB_FILE);
        WriteCovDb(ErrorCov, ERROR_COV_DB_FILE);
        WriteCovDb(SpeedCov, SPEED_COV_DB_FILE);

        TranscriptClose;
        EndOfTestReports;
        std.env.stop;
        wait;
    end process ControlProc;

    ------------------------------------------------------------
    -- Controller-side stimulus
    ------------------------------------------------------------
    ControllerProc : process
        variable RData : std_logic_vector(7 downto 0);
    begin
        wait until n_Reset = '1';
        WaitForClock(I2cControllerRec, 2);

        Write(I2cControllerRec, DEV_ADDR, WDATA);
        ICover(AddrCov, (1, I2cAddrRangeBucket(DEV_ADDR, 10)));
        ICover(XferCov, 1);
        ICover(RwSrCov, (0, 0));
        ICover(ErrorCov, I2cErrorKindType'pos(ERR_NONE));
        ICover(SpeedCov, 2);

        Read(I2cControllerRec, DEV_ADDR, RData);
        AffirmIfEqual(RData, RDATA, "Controller received read data");
        ICover(AddrCov, (1, I2cAddrRangeBucket(DEV_ADDR, 10)));
        ICover(XferCov, 1);
        ICover(RwSrCov, (1, 0));
        ICover(ErrorCov, I2cErrorKindType'pos(ERR_NONE));
        ICover(SpeedCov, 2);

        WaitForBarrier(TestDone);
        wait;
    end process ControllerProc;

    ------------------------------------------------------------
    -- Peripheral-side stimulus / checking
    ------------------------------------------------------------
    PeripheralProc : process
        variable RxAddr : std_logic_vector(9 downto 0);
        variable RxData : std_logic_vector(7 downto 0);
    begin
        wait until n_Reset = '1';

        GetWrite(I2cPeripheralRec, RxAddr, RxData);
        AffirmIfEqual(RxAddr, DEV_ADDR, "Peripheral received write address");
        AffirmIfEqual(RxData, WDATA, "Peripheral received data");

        SendRead(I2cPeripheralRec, RxAddr, RDATA);
        AffirmIfEqual(RxAddr, DEV_ADDR, "Peripheral received read address");

        WaitForBarrier(TestDone);
        wait;
    end process PeripheralProc;

end architecture Addr10_1;

configuration TbI2c_Addr10_1 of TbI2c is
    for TestHarness
        for TestCtrl_1 : TestCtrl
            use entity work.TestCtrl(Addr10_1);
        end for;
        for I2cPeripheral_1 : I2cPeripheral
            use entity osvvm_i2c.I2cPeripheral
                generic map (
                    TARGET_ADDRESS => "1111000001",
                    TEN_BIT_ADDR   => true
                );
        end for;
    end for;
end configuration TbI2c_Addr10_1;
