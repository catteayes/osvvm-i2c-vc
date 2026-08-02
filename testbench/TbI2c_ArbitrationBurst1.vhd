--
--  File Name:         TbI2c_ArbitrationBurst1.vhd
--  Design Unit Name:  architecture ArbitrationBurst1 of TestCtrlArb
--
--  Maintainer:        Mehmet Burak Aykenar    email: burak.aykenar@anadologic.com
--  Contributor(s):
--     <intern name>
--
--  Description:
--      Multi-master arbitration test with WriteBurst. Both controllers
--      target the SAME address (DEV_ADDR), they diverge on the first data
--      byte's second bit: Controller A's first byte is X"11" (bit 6 = 0),
--      Controller B's is X"51" (bit 6 = 1). Both share bit 7 (the MSB is 0
--      for both). So B loses arbitration.
--
--  Revision History:
--    Date      Version    Description
--    08/2026   0.1        Initial arbitration + WriteBurst test (#16)
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

architecture ArbitrationBurst1 of TestCtrlArb is

    signal TestDone : integer_barrier := 1;

    constant DEV_ADDR : std_logic_vector(6 downto 0) := "1010000";

    -- B loses arbitration on the second bit of the first data byte.
    constant WBYTES_A : slv_vector(0 to 2)(7 downto 0) := (X"11", X"22", X"33");
    constant WBYTES_B : slv_vector(0 to 1)(7 downto 0) := (X"51", X"55");

begin

    ------------------------------------------------------------
    -- Test global control
    ------------------------------------------------------------
    ControlProc : process
    begin
        SetTestName("TbI2c_ArbitrationBurst1");
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
        -- 1 WARNING alert (arbitration loss) is expected.
        EndOfTestReports(ExternalErrors => (FAILURE => 0, ERROR => 0, WARNING => -1));
        std.env.stop;
        wait;
    end process ControlProc;

    ------------------------------------------------------------
    -- Controller A: wins arbitration, WriteBurst completes normally.
    ------------------------------------------------------------
    ControllerAProc : process
    begin
        wait until n_Reset = '1';
        WaitForClock(I2cController1Rec, 2);

        WriteBurstVector(I2cController1Rec, DEV_ADDR, WBYTES_A);

        WaitForBarrier(TestDone);
        wait;
    end process ControllerAProc;

    ------------------------------------------------------------
    -- Controller B: loses arbitration to A on the first data byte,
    -- auto-retries the whole burst once the bus frees.
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

        WriteBurstVector(I2cController2Rec, DEV_ADDR, WBYTES_B);

        Count1 := GetAlertCount(BAlertLogID);
        AffirmIfEqual(Count1, Count0 + 1,
            "Alert count after Controller B's arbitration loss (WARNING)");

        WaitForBarrier(TestDone);
        wait;
    end process ControllerBProc;

    ------------------------------------------------------------
    -- Peripheral: sees Controller A's burst first (it wins and finishes
    -- normally), then Controller B's retried burst.
    ------------------------------------------------------------
    PeripheralProc : process
        variable RxAddr : std_logic_vector(6 downto 0);
        variable RxData : std_logic_vector(7 downto 0);
    begin
        wait until n_Reset = '1';

        for i in WBYTES_A'range loop
            GetWrite(I2cPeripheralRec, RxAddr, RxData);
            if i = WBYTES_A'low then
                AffirmIfEqual(RxAddr, DEV_ADDR, "Peripheral received Controller A's burst address (arbitration winner)");
            end if;
            AffirmIfEqual(RxData, WBYTES_A(i), "Peripheral received Controller A's burst byte " & to_string(i));
        end loop;

        for i in WBYTES_B'range loop
            GetWrite(I2cPeripheralRec, RxAddr, RxData);
            if i = WBYTES_B'low then
                AffirmIfEqual(RxAddr, DEV_ADDR, "Peripheral received Controller B's retried burst address");
            end if;
            AffirmIfEqual(RxData, WBYTES_B(i), "Peripheral received Controller B's retried burst byte " & to_string(i));
        end loop;

        WaitForBarrier(TestDone);
        wait;
    end process PeripheralProc;

end architecture ArbitrationBurst1;

configuration TbI2c_ArbitrationBurst1 of TbI2cArb is
    for TestHarness
        for TestCtrl_1 : TestCtrlArb
            use entity work.TestCtrlArb(ArbitrationBurst1);
        end for;
    end for;
end configuration TbI2c_ArbitrationBurst1;
