--
--  File Name:         TbI2c_Arbitration1.vhd
--  Design Unit Name:  architecture Arbitration1 of TestCtrlArb
--
--  Maintainer:        Mehmet Burak Aykenar    email: burak.aykenar@anadologic.com
--  Contributor(s):
--     <intern name>
--
--  Description:
--      Multi-master arbitration test: two controllers start a Write at the same
--      time. DEV_ADDR_A = "1010000", DEV_ADDR_B = "1011000". Controller A drives
--      a '0' there while Controller B wants '1' (released), so Controller B loses
--      arbitration. Controller B has auto-retry enabled: after losing (one WARNING
--      alert). It waits for the bus to go idle (Controller A's STOP) and retries
--      but DEV_ADDR_B isn't owned by any peripheral, so the retry just gets a
--      normal NACK (1 ERROR alert) which is verified with alert-count checking.
--
--  Revision History:
--    Date      Version    Description
--    07/2026   0.1        Initial multi-master arbitration test (#16)
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

architecture Arbitration1 of TestCtrlArb is

    signal TestDone : integer_barrier := 1;

    -- DEV_ADDR_A matches I2cPeripheral_1's default TARGET_ADDRESS (0x50).
    constant DEV_ADDR_A : std_logic_vector(6 downto 0) := "1010000";
    constant DEV_ADDR_B : std_logic_vector(6 downto 0) := "1011000";
    constant WDATA_A    : std_logic_vector(7 downto 0) := X"11";
    constant WDATA_B    : std_logic_vector(7 downto 0) := X"22";

begin

    ------------------------------------------------------------
    -- Test global control
    ------------------------------------------------------------
    ControlProc : process
    begin
        SetTestName("TbI2c_Arbitration1");
        SetLogEnable(PASSED, TRUE);
        SetLogEnable(DEBUG, TRUE);

        wait for 0 ns;  wait for 0 ns;
        TranscriptOpen;
        SetTranscriptMirror(TRUE);

        wait until n_Reset = '1';
        ClearAlerts;

        WaitForBarrier(TestDone, 10 ms);
        AlertIf(now >= 10 ms, "Test finished due to timeout");

        TranscriptClose;
        -- 1 ERROR alert (Controller B trying to write to a non-existent address)
        -- and 1 WARNING alert (arbitration loss) are expected.
        EndOfTestReports(ExternalErrors => (FAILURE => 0, ERROR => -1, WARNING => -1));
        std.env.stop;
        wait;
    end process ControlProc;

    ------------------------------------------------------------
    -- Controller A: wins arbitration, write completes normally.
    ------------------------------------------------------------
    ControllerAProc : process
    begin
        wait until n_Reset = '1';
        WaitForClock(I2cController1Rec, 2);

        Write(I2cController1Rec, DEV_ADDR_A, WDATA_A);

        WaitForBarrier(TestDone);
        wait;
    end process ControllerAProc;

    ------------------------------------------------------------
    -- Controller B: loses arbitration to A, auto-retries once the bus
    -- frees, then gets a normal NACK (no peripheral has address DEV_ADDR_B).
    ------------------------------------------------------------
    ControllerBProc : process
        variable BAlertLogID    : AlertLogIDType;
        variable Count0, Count1 : integer;
    begin
        wait until n_Reset = '1';
        WaitForClock(I2cController2Rec, 2);

        GetAlertLogID(I2cController2Rec, BAlertLogID);
        SetAlertStopCount(BAlertLogID, ERROR, 10);

        Count0 := GetAlertCount(BAlertLogID);
        SetArbitrationAutoRetry(I2cController2Rec, TRUE);

        Write(I2cController2Rec, DEV_ADDR_B, WDATA_B);

        Count1 := GetAlertCount(BAlertLogID);
        AffirmIfEqual(Count1, Count0 + 2,
            "Alert count after Controller B's arbitration loss (WARNING) and NACK (ERROR)");

        WaitForBarrier(TestDone);
        wait;
    end process ControllerBProc;

    ------------------------------------------------------------
    -- Peripheral: only Controller A's write ever reaches it, Controller
    -- B doesnt get far enough to be addressed (loses arbitration, then
    -- targets an address nothing here owns).
    ------------------------------------------------------------
    PeripheralProc : process
        variable RxAddr : std_logic_vector(6 downto 0);
        variable RxData : std_logic_vector(7 downto 0);
    begin
        wait until n_Reset = '1';

        GetWrite(I2cPeripheralRec, RxAddr, RxData);
        AffirmIfEqual(RxAddr, DEV_ADDR_A, "Peripheral received write address (Controller A, the arbitration winner)");
        AffirmIfEqual(RxData, WDATA_A, "Peripheral received data");

        WaitForBarrier(TestDone);
        wait;
    end process PeripheralProc;

end architecture Arbitration1;

configuration TbI2c_Arbitration1 of TbI2cArb is
    for TestHarness
        for TestCtrl_1 : TestCtrlArb
            use entity work.TestCtrlArb(Arbitration1);
        end for;
    end for;
end configuration TbI2c_Arbitration1;
