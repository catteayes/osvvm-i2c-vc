# OSVVM I2C Verification Component

I2C Verification Component library for [OSVVM](https://osvvm.org), including controller (master), peripheral (slave/target), regression tests, and documentation.

Structured like the VCs inside [OsvvmLibraries](https://github.com/OSVVM/OsvvmLibraries) (see `SPI_GuyEschemann` and `UART`) so it can be contributed upstream as a submodule when mature. Licensed under Apache-2.0 to match OSVVM.

## Getting started

Clone **recursively** — OsvvmLibraries is a submodule that itself contains submodules:

```
git clone --recursive https://github.com/anadologic/osvvm-i2c-vc.git
```

(If already cloned: `git submodule update --init --recursive`)

## Building and running the regression

Uses the OSVVM script system with any supported simulator (GHDL and NVC are free and work well). From your simulation directory, in the simulator's Tcl shell:

```tcl
source <repo>/OsvvmLibraries/Scripts/StartUp.tcl
build  <repo>/OsvvmLibraries/OsvvmLibraries.pro   ;# osvvm + Common + reference VCs (once)
build  <repo>/RunAllTests.pro                     ;# I2C VC + regression
```

Test results and reports land in the simulation directory (`reports/`, `logs/`, `results/`). See the [OSVVM Script User Guide](https://github.com/OSVVM/Documentation) for details.

## Repository layout

```
src/                 I2C verification components (library osvvm_i2c)
  I2cTbPkg.vhd         types, constants, transaction record
  I2cComponentPkg.vhd  component declarations
  I2cContext.vhd       context declaration
  I2cController.vhd    I2C controller (master) VC
  I2cPeripheral.vhd    I2C peripheral (target/slave) VC
testbench/           OSVVM test harness + one file per test case
build.pro            compiles src/ into osvvm_i2c
RunAllTests.pro      full regression
OsvvmLibraries/      submodule: OSVVM utility lib, Common (MIT), Scripts, reference VCs
```

## Development workflow

- Work happens on feature branches; every change lands on `main` via a reviewed pull request.
- Each task is a GitHub issue, grouped into milestones. The regression (`RunAllTests.pro`) must pass before merge.
- Reference reading order for new contributors: OSVVM `Documentation` overview, then the `UART` VC (canonical simple VC), then `SPI_GuyEschemann` (a community-contributed VC that this repo is modeled on), then `Common/src/AddressBusTransactionPkg.vhd` (Model Independent Transactions).

## References

- I2C-bus specification: NXP UM10204
- [OSVVM Documentation](https://github.com/OSVVM/Documentation)
- [OsvvmLibraries](https://github.com/OSVVM/OsvvmLibraries)
