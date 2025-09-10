# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains Verilog source code for implementing the RHS2000 7310 Rhythm Stim USB3 Interface using the Opal Kelly XEM7310 USB/FPGA board. The design interfaces multiple Intan Technologies RHS2000-series chips to a computer via a USB 3.0 connection.

## Code Architecture and Structure

The design consists of several key modules:

1. **Main Module** (`main.v`): Top-level module that instantiates all major components and connects them to the Opal Kelly XEM7310 board interfaces.

2. **Opal Kelly Integration**: Uses Opal Kelly's FrontPanel interface with modules like:
   - `okCoreHarness.v`: Core harness for Opal Kelly interface
   - `okLibrary.v`: Library of Opal Kelly interface components
   - `okWireIn.v`, `okWireOut.v`: Wire interface modules
   - `okTriggerIn.v`: Trigger input module
   - `okPipeIn.v`: Pipe input module
   - `okBTPipeOut.v`: Block transfer pipe output module

3. **Data Acquisition Components**:
   - `ADC_input.v`: Analog-to-digital converter input handling
   - `digital_input_deserializer.v`: Digital input deserialization
   - `MISO_phase_selector.v`: MISO phase selection for SPI communications

4. **Data Output Components**:
   - `DAC_output_scalable_HPF.v`: Digital-to-analog converter output with scalable high-pass filtering
   - `analog_out_sequencer.v`: Analog output sequencing
   - `digout_sequencer.v`: Digital output sequencing
   - `stim_sequencer.v`: Stimulation sequencing

5. **Memory Interface**:
   - `ddr3_state_machine.v`: DDR3 memory controller state machine
   - `RAM_bank.v`, `RAM_block.v`: Memory storage components
   - `SDRAM_FIFO.v`: SDRAM FIFO buffering

6. **Clock Generation**:
   - `variable_freq_clk_generator.v`: Variable frequency clock generator
   - `mmcm_drp.v`: Mixed-mode clock manager with dynamic reconfiguration

## Build Process

This is a Xilinx Vivado FPGA project. The build process requires:

1. Create a new Vivado RTL project for part `xc7a75tfgg484-1`
2. Add all Verilog source files and constraint files to the project
3. Generate required IP cores:
   - `ddr3_256_32`: DDR3 memory interface (using MIG 7 Series)
   - `fifo_w16_256_r32_128`: FIFO with 16-bit input/32-bit output
   - `fifo_w32_2048_r256_256`: FIFO with 32-bit input/256-bit output
   - `fifo_w256_8192_r32_65536`: FIFO with 256-bit input/32-bit output
   - `multiplier_18x18`: 18-bit parallel multiplier

4. Constraint files:
   - `xem7310.xdc`: Main constraints file
   - `xem7310_sdram.xdc`: SDRAM-specific constraints (used only for IP generation)

5. Generate bitstream through synthesis and implementation

Detailed step-by-step instructions for setting up the project are provided in `README.txt`.

## Key Files

- `main.v`: Top-level module
- `README.txt`: Project setup instructions
- `*.v`: Verilog source files for various functional modules
- `*.xdc`: Xilinx Design Constraints files
- `mmcm_drp_func.h`: Header file with MMCM DRP functions