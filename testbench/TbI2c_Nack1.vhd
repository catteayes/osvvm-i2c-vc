--
--  File Name:         TbI2c_Nack1.vhd
--  Design Unit Name:  architecture Nack1 of TestCtrl
--
--  Maintainer:        Mehmet Burak Aykenar    email: burak.aykenar@anadologic.com
--  Contributor(s):
--     <intern name>
--
--  Description:
--      NACK injection test: the peripheral is forced to NACK the address
--      byte, then forced to NACK a write-data byte, on two separate write
--      attempts. A third normal write afterward confirms the VCs keep working normally.
--      Then the controller is forced to Nack mid-ReadBurst.
--
--  Revision History:
--    Date      Version    Description
--    08/2026   0.2        Functional coverage (#18)
--    07/2026   0.1        NACK injection test (#12)
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

library osvvm;
    use osvvm.ScoreboardPkg_slv.all;

architecture Nack1 of TestCtrl is

    signal TestDone : integer_barrier := 1;
    signal Sync1     : integer_barrier := 1;

    constant DEV_ADDR : std_logic_vector(6 downto 0) := "1010000";
    constant WDATA1   : std_logic_vector(7 downto 0) := X"AB";  -- address-NACK attempt
    constant WDATA2   : std_logic_vector(7 downto 0) := X"CD";  -- data-NACK attempt
    constant WDATA3   : std_logic_vector(7 downto 0) := X"EF";  -- check

    -- Read-NACK-injection scenario: 3 bytes queued, but the controller
    -- injects a NACK at (0-based) index 1, so only bytes 0 and 1 ever go
    -- out on the wire - RDATA2 is never sent.
    constant RDATA0 : std_logic_vector(7 downto 0) := X"11";
    constant RDATA1 : std_logic_vector(7 downto 0) := X"22";

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
        SetTestName("TbI2c_Nack1");
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
        -- 3 ERROR alerts (address NACK, write-data NACK, read-data NACK) are expected.
        EndOfTestReports(ExternalErrors => (FAILURE => 0, ERROR => -3, WARNING => 0));
        std.env.stop;
        wait;
    end process ControlProc;

    ------------------------------------------------------------
    -- Controller-side stimulus
    ------------------------------------------------------------
    ControllerProc : process
        variable CtrlAlertLogID                 : AlertLogIDType;
        variable Count0, Count1, Count2, Count3  : integer;
        variable Discard                         : std_logic_vector(7 downto 0);
    begin
        wait until n_Reset = '1';
        WaitForClock(I2cControllerRec, 2);

        SetSclPeriod(I2cControllerRec, I2C_SCL_PERIOD_100K);  -- Standard-mode, for SpeedCov

        GetAlertLogID(I2cControllerRec, CtrlAlertLogID);
        SetAlertStopCount(CtrlAlertLogID, ERROR, 10);  -- so injected NACKs dont stop the sim

        Count0 := GetAlertCount(CtrlAlertLogID);

        -- 1) periapheral NACKS the address: Must STOP and raise one ERROR alert.
        Write(I2cControllerRec, DEV_ADDR, WDATA1);
        ICover(AddrCov, (0, I2cAddrRangeBucket(DEV_ADDR, 7)));
        ICover(XferCov, 1);
        ICover(RwSrCov, (0, 0));
        ICover(ErrorCov, I2cErrorKindType'pos(ERR_NACK));
        ICover(SpeedCov, 1);
        Count1 := GetAlertCount(CtrlAlertLogID);
        AffirmIfEqual(Count1, Count0 + 1, "Alert count after address-NACK write");

        WaitForBarrier(Sync1);

        -- 2) peripheral NACKs the data byte: Must STOP and raise one ERROR alert.
        Write(I2cControllerRec, DEV_ADDR, WDATA2);
        ICover(AddrCov, (0, I2cAddrRangeBucket(DEV_ADDR, 7)));
        ICover(XferCov, 1);
        ICover(RwSrCov, (0, 0));
        ICover(ErrorCov, I2cErrorKindType'pos(ERR_NACK));
        ICover(SpeedCov, 1);
        Count2 := GetAlertCount(CtrlAlertLogID);
        AffirmIfEqual(Count2, Count1 + 1, "Alert count after data-NACK write");

        -- 3) check: a normal write raises no further alerts.
        Write(I2cControllerRec, DEV_ADDR, WDATA3);
        ICover(AddrCov, (0, I2cAddrRangeBucket(DEV_ADDR, 7)));
        ICover(XferCov, 1);
        ICover(RwSrCov, (0, 0));
        ICover(ErrorCov, I2cErrorKindType'pos(ERR_NONE));
        ICover(SpeedCov, 1);
        AffirmIfEqual(GetAlertCount(CtrlAlertLogID), Count2,
            "Alert count unchanged after recovery write");

        -- 4) controller-side: force an early NACK on ReadBurst byte index 1
        -- (0-based), raises one ERROR alert.
        Count3 := GetAlertCount(CtrlAlertLogID);
        SetNackInjectDataByte(I2cControllerRec, 1);
        ReadBurst(I2cControllerRec, DEV_ADDR, 3);
        ICover(AddrCov, (0, I2cAddrRangeBucket(DEV_ADDR, 7)));
        ICover(XferCov, 3);
        ICover(RwSrCov, (1, 0));
        ICover(ErrorCov, I2cErrorKindType'pos(ERR_NACK));
        ICover(SpeedCov, 1);
        AffirmIfEqual(Pop(I2cControllerRec.ReadBurstFifo), RDATA0,
            "Read burst byte 0 before injected NACK");
        AffirmIfEqual(Pop(I2cControllerRec.ReadBurstFifo), RDATA1,
            "Read burst byte 1 (injected NACK ends the read here)");
        Discard := Pop(I2cControllerRec.ReadBurstFifo);  -- placeholder: byte 2 was never sent
        AffirmIfEqual(GetAlertCount(CtrlAlertLogID), Count3 + 1,
            "Alert count after controller-injected read NACK");

        WaitForBarrier(TestDone);
        wait;
    end process ControllerProc;

    ------------------------------------------------------------
    -- Peripheral-side stimulus / checking
    ------------------------------------------------------------
    PeripheralProc : process
        variable RxAddr : std_logic_vector(6 downto 0);
        variable RxData : std_logic_vector(7 downto 0);
    begin
        wait until n_Reset = '1';

        -- 1) force a NACK on the next address byte.
        SetNackInjectAddress(I2cPeripheralRec);
        WaitForBarrier(Sync1);

        -- 2) force a NACK on write-data byte index 0 of the next write.
        SetNackInjectDataByte(I2cPeripheralRec, 0);

        -- 3) check: write completes normally.
        GetWrite(I2cPeripheralRec, RxAddr, RxData);
        AffirmIfEqual(RxAddr, DEV_ADDR, "Peripheral received write address");
        AffirmIfEqual(RxData, WDATA3, "Peripheral received write data");

        -- 4) controller-side read NACK injection
        SendRead(I2cPeripheralRec, RxAddr, RDATA0);
        AffirmIfEqual(RxAddr, DEV_ADDR, "Peripheral received read address (injected-NACK scenario)");
        SendRead(I2cPeripheralRec, RxAddr, RDATA1);

        WaitForBarrier(TestDone);
        wait;
    end process PeripheralProc;

end architecture Nack1;

configuration TbI2c_Nack1 of TbI2c is
    for TestHarness
        for TestCtrl_1 : TestCtrl
            use entity work.TestCtrl(Nack1);
        end for;
    end for;
end configuration TbI2c_Nack1;
