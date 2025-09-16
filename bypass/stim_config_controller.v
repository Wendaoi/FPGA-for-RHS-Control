`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:        (User-Generated)
// Design Name:    Stimulation Sequencer Configuration Controller
// Module Name:    stim_config_controller
// Description:    Takes a high-level frequency target and automatically 
//                 configures a specified stim_sequencer module over several
//                 clock cycles using a state machine.
//
//                 This module is designed to be integrated into 'main.v'.
//////////////////////////////////////////////////////////////////////////////////

module stim_config_controller #(
    // This parameter MUST match the actual frequency of 'dataclk' set in main.v
    parameter DATACLK_HZ = 30000 
)
(
    // --- Control Interface ---
    input wire          clk,                // System clock for the state machine (e.g., okClk)
    input wire          reset,              // Asynchronous or synchronous reset
    input wire          start_config,       // A one-cycle pulse to begin the configuration sequence

    // --- Configuration Parameters ---
    input wire [4:0]    target_module,      // The 'MODULE' parameter of the stim_sequencer to configure (0-7)
    input wire [3:0]    target_channel,     // The channel within the sequencer to configure (0-15)
    input wire [15:0]   target_freq_hz,     // Desired stimulation frequency in Hz (e.g., 4 to 40)

    // --- Outputs to main.v stim_sequencer programming interface ---
    output reg [4:0]    prog_module,
    output reg [3:0]    prog_channel,
    output reg [3:0]    prog_address,
    output reg [15:0]   prog_word,
    output reg          prog_trig,

    // --- Status Outputs ---
    output reg          config_busy,        // High while the configuration sequence is active
    output reg          config_done         // A one-cycle pulse indicating the sequence has finished
);

//----------------------------------------------------------------
// Internal Registers and Wires
//----------------------------------------------------------------

// State machine definition
localparam [4:0]
    IDLE            = 5'd0,
    CALC_AND_LATCH  = 5'd1,
    SET_ADDR_0      = 5'd2,  // Configure Trigger
    TRIG_ADDR_0     = 5'd3,
    SET_ADDR_1      = 5'd4,  // Configure Stim Shape
    TRIG_ADDR_1     = 5'd5,
    SET_ADDR_4      = 5'd6,  // event_start_stim
    TRIG_ADDR_4     = 5'd7,
    SET_ADDR_5      = 5'd8,  // event_stim_phase2
    TRIG_ADDR_5     = 5'd9,
    SET_ADDR_7      = 5'd10, // event_end_stim
    TRIG_ADDR_7     = 5'd11,
    SET_ADDR_13     = 5'd12, // event_end (This sets the frequency)
    TRIG_ADDR_13    = 5'd13,
    DONE            = 5'd14;

reg [4:0] state, next_state;

// Register addresses for stim_sequencer
localparam ADDR_TRIG_CFG        = 4'd0;
localparam ADDR_SHAPE_CFG       = 4'd1;
localparam ADDR_EVT_AMP_SETTLE_ON = 4'd2;
localparam ADDR_EVT_START_STIM  = 4'd4;
localparam ADDR_EVT_PHASE2      = 4'd5;
localparam ADDR_EVT_END_STIM    = 4'd7;
localparam ADDR_EVT_END         = 4'd13;

// Calculated value for event_end register
reg [15:0] event_end_calculated;

// Latched versions of the inputs
reg [4:0]  target_module_reg;
reg [3:0]  target_channel_reg;

//----------------------------------------------------------------
// Logic Implementation
//----------------------------------------------------------------

// Calculation for event_end based on target frequency
// This happens combinatorially.
always @(*) begin
    if (target_freq_hz > 0) begin
        // The core formula: event_end = (dataclk_freq / stim_freq) - 1
        event_end_calculated = (DATACLK_HZ / target_freq_hz) - 1;
    end else begin
        // Provide a safe default if frequency is zero to avoid division by zero
        event_end_calculated = 16'hFFFF; 
    end
end

// State Register
always @(posedge clk or posedge reset) begin
    if (reset) begin
        state <= IDLE;
    end else begin
        state <= next_state;
    end
end

// FSM Combinatorial Logic (State transitions and outputs)
always @(*) begin
    // Default assignments to avoid latches
    next_state = state;
    prog_module = target_module_reg;
    prog_channel = target_channel_reg;
    prog_address = 4'b0;
    prog_word = 16'b0;
    prog_trig = 1'b0;
    config_busy = 1'b1; // Busy by default unless in IDLE
    config_done = 1'b0;

    case (state)
        IDLE: begin
            config_busy = 1'b0;
            if (start_config) begin
                next_state = CALC_AND_LATCH;
            end
        end

        CALC_AND_LATCH: begin
            // Latch inputs at the beginning of the sequence
            target_module_reg <= target_module;
            target_channel_reg <= target_channel;
            next_state = SET_ADDR_0;
        end

        // --- Step 1: Configure Trigger (Address 0) ---
        SET_ADDR_0: begin
            prog_address = ADDR_TRIG_CFG;
            // Config: Enable, level-triggered, high-polarity, source = manual_triggers[0]
            prog_word = {8'b0, 1'b1, 1'b1, 1'b0, 5'b01000}; 
            next_state = TRIG_ADDR_0;
        end
        TRIG_ADDR_0: begin
            prog_address = ADDR_TRIG_CFG;
            prog_word = {8'b0, 1'b1, 1'b1, 1'b0, 5'b01000};
            prog_trig = 1'b1;
            next_state = SET_ADDR_1;
        end

        // --- Step 2: Configure Stimulus Shape (Address 1) ---
        SET_ADDR_1: begin
            prog_address = ADDR_SHAPE_CFG;
            // Config: Biphasic pulse, 1 pulse in the train
            prog_word = {5'b0, 1'b0, 2'b00, 8'd1}; 
            next_state = TRIG_ADDR_1;
        end
        TRIG_ADDR_1: begin
            prog_address = ADDR_SHAPE_CFG;
            prog_word = {5'b0, 1'b0, 2'b00, 8'd1};
            prog_trig = 1'b1;
            next_state = SET_ADDR_4;
        end

        // --- Step 3: Define a simple pulse waveform ---
        SET_ADDR_4: begin // event_start_stim
            prog_address = ADDR_EVT_START_STIM;
            prog_word = 16'd10; // Start stim at cycle 10
            next_state = TRIG_ADDR_4;
        end
        TRIG_ADDR_4: begin
            prog_address = ADDR_EVT_START_STIM;
            prog_word = 16'd10;
            prog_trig = 1'b1;
            next_state = SET_ADDR_5;
        end
        SET_ADDR_5: begin // event_stim_phase2
            prog_address = ADDR_EVT_PHASE2;
            prog_word = 16'd30; // Switch to phase 2 at cycle 30
            next_state = TRIG_ADDR_5;
        end
        TRIG_ADDR_5: begin
            prog_address = ADDR_EVT_PHASE2;
            prog_word = 16'd30;
            prog_trig = 1'b1;
            next_state = SET_ADDR_7;
        end
        SET_ADDR_7: begin // event_end_stim
            prog_address = ADDR_EVT_END_STIM;
            prog_word = 16'd50; // End stim at cycle 50
            next_state = TRIG_ADDR_7;
        end
        TRIG_ADDR_7: begin
            prog_address = ADDR_EVT_END_STIM;
            prog_word = 16'd50;
            prog_trig = 1'b1;
            next_state = SET_ADDR_13;
        end
        
        // --- Step 4: Set the waveform period (event_end) ---
        // THIS IS THE KEY STEP FOR FREQUENCY CONTROL
        SET_ADDR_13: begin
            prog_address = ADDR_EVT_END;
            prog_word = event_end_calculated; // Use the calculated value
            next_state = TRIG_ADDR_13;
        end
        TRIG_ADDR_13: begin
            prog_address = ADDR_EVT_END;
            prog_word = event_end_calculated;
            prog_trig = 1'b1;
            next_state = DONE;
        end

        // --- Finish sequence ---
        DONE: begin
            config_done = 1'b1;
            next_state = IDLE;
        end

        default: begin
            next_state = IDLE;
        end
    endcase
end

endmodule