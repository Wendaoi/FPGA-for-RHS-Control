`timescale 1ns/1ps

// =============================================================================
// 模块名称: enhanced_bypass_controller
// 描述:    增强型旁路控制器，支持电极分组功能
//          该模块生成刺激序列器控制信号，用于控制下级设备
//          同时集成了游戏控制、数据处理和电极分组管理功能
// =============================================================================

module enhanced_bypass_controller #(
    parameter DATA_WIDTH = 16,          // 数据宽度 (默认16位)
    parameter CHANNELS = 8,             // 通道数量 (默认8通道)
    parameter CMD_WIDTH = 32,           // 命令宽度 (默认32位)
    parameter GROUPS = 10,              // 电极分组数量 (默认10组)
    parameter ELECTRODES_PER_GROUP = 8  // 每组电极数量 (默认每组8个电极)
) (
    // -------------------------------------------------------------------------
    // 系统时钟和复位信号
    // -------------------------------------------------------------------------
    input wire clk,                     // 系统时钟
    input wire reset,                   // 系统复位信号 (高电平有效)
    
    // -------------------------------------------------------------------------
    // 控制接口 - 从WireIn端点接收控制命令
    // -------------------------------------------------------------------------
    input wire bypass_enable,           // 旁路功能启用信号 (1:启用旁路, 0:禁用旁路)
    input wire [31:0] command_data,     // 待发送的32位命令数据
    input wire command_valid,           // 命令数据有效信号 (1:数据有效)
    input wire [1:0] spi_mode,          // SPI模式选择 (00:模式0, 01:模式1, 10:模式2, 11:模式3)
    input wire auto_cs_n,               // 自动CS_N控制 (0:自动控制, 1:手动控制)
    input wire manual_cs_n,             // 手动CS_N控制 (当auto_cs_n=1时有效)
    input wire [1:0] game_mode,         // 游戏模式选择 (00:闭环反馈, 01:静默反馈, 10:无反馈, 11:对照组)
    
    // -------------------------------------------------------------------------
    // RHS芯片数据输入接口
    // -------------------------------------------------------------------------
    input wire [DATA_WIDTH-1:0] rhs_data_in [0:CHANNELS-1],  // RHS芯片数据输入 (每个通道DATA_WIDTH位)
    input wire rhs_data_valid,                               // RHS数据有效信号
    
    // -------------------------------------------------------------------------
    // 游戏模块接口
    // -------------------------------------------------------------------------
    input wire game_start_valid,        // 游戏开始信号有效
    output wire game_start_ready,       // 游戏开始准备就绪
    input wire game_end_valid,          // 游戏结束信号有效
    output wire game_end_ready,         // 游戏结束准备就绪
    input wire [1:0] paddle_control,    // 桨控制信号
    output wire result_en,              // 结果使能信号
    output wire game_result,            // 游戏结果信号
    output wire [7:0] ball_x,           // 球X坐标
    output wire [7:0] ball_y,           // 球Y坐标
    output reg [7:0] win_counter,       // 获胜计数器
    output reg [7:0] lose_counter,      // 失败计数器
    
    // -------------------------------------------------------------------------
    // 状态反馈 - 通过WireOut端点输出状态信息
    // -------------------------------------------------------------------------
    output reg [31:0] response_data,    // 接收到的32位响应数据
    output reg response_valid,          // 响应数据有效信号 (1:数据有效)
    output reg busy,                    // 模块忙信号 (1:模块忙碌)
    
    // -------------------------------------------------------------------------
    // 刺激序列器控制接口 - 连接到刺激序列器模块
    // -------------------------------------------------------------------------
    output reg stim_cmd_valid,          // 刺激命令有效信号
    output reg [5:0] stim_channel,      // 刺激通道选择 (0-15: convert, 16-19: stim)
    output reg stim_shutdown,           // 安全关闭信号 (高有效)
    // Individual channel control signals
    output reg [15:0] stim_on_A1,       // A1通道刺激开启控制
    output reg [15:0] stim_pol_A1,      // A1通道刺激极性控制
    output reg [15:0] stim_amp_settle_A1, // A1通道放大器稳定控制
    output reg [15:0] stim_charge_recov_A1, // A1通道电荷恢复控制
    output reg [15:0] stim_on_A2,       // A2通道刺激开启控制
    output reg [15:0] stim_pol_A2,      // A2通道刺激极性控制
    output reg [15:0] stim_amp_settle_A2, // A2通道放大器稳定控制
    output reg [15:0] stim_charge_recov_A2, // A2通道电荷恢复控制
    output reg [15:0] stim_on_B1,       // B1通道刺激开启控制
    output reg [15:0] stim_pol_B1,      // B1通道刺激极性控制
    output reg [15:0] stim_amp_settle_B1, // B1通道放大器稳定控制
    output reg [15:0] stim_charge_recov_B1, // B1通道电荷恢复控制
    output reg [15:0] stim_on_B2,       // B2通道刺激开启控制
    output reg [15:0] stim_pol_B2,      // B2通道刺激极性控制
    output reg [15:0] stim_amp_settle_B2, // B2通道放大器稳定控制
    output reg [15:0] stim_charge_recov_B2, // B2通道电荷恢复控制
    output reg [15:0] stim_on_C1,       // C1通道刺激开启控制
    output reg [15:0] stim_pol_C1,      // C1通道刺激极性控制
    output reg [15:0] stim_amp_settle_C1, // C1通道放大器稳定控制
    output reg [15:0] stim_charge_recov_C1, // C1通道电荷恢复控制
    output reg [15:0] stim_on_C2,       // C2通道刺激开启控制
    output reg [15:0] stim_pol_C2,      // C2通道刺激极性控制
    output reg [15:0] stim_amp_settle_C2, // C2通道放大器稳定控制
    output reg [15:0] stim_charge_recov_C2, // C2通道电荷恢复控制
    output reg [15:0] stim_on_D1,       // D1通道刺激开启控制
    output reg [15:0] stim_pol_D1,      // D1通道刺激极性控制
    output reg [15:0] stim_amp_settle_D1, // D1通道放大器稳定控制
    output reg [15:0] stim_charge_recov_D1, // D1通道电荷恢复控制
    output reg [15:0] stim_on_D2,       // D2通道刺激开启控制
    output reg [15:0] stim_pol_D2,      // D2通道刺激极性控制
    output reg [15:0] stim_amp_settle_D2, // D2通道放大器稳定控制
    output reg [15:0] stim_charge_recov_D2, // D2通道电荷恢复控制
    output reg stim_amp_settle_changed, // 放大器稳定控制改变信号
    input wire stim_cmd_ready,          // 刺激命令就绪信号
);

// -------------------------------------------------------------------------
// 内部信号定义
// -------------------------------------------------------------------------

// 刺激控制状态机信号
reg [3:0] state, next_state;        // 当前状态和下一状态寄存器
reg [31:0] command_reg;             // 命令寄存器，存储待处理的命令
reg command_reg_valid;              // 命令寄存器有效标志
reg command_processed;              // 命令处理完成标志
reg cmd_delay_counter;              // 命令延迟计数器

// -------------------------------------------------------------------------
// 电极分组控制信号
// -------------------------------------------------------------------------

// 电极分组映射表
// group_map[组号][电极号] = 实际电极编号
// 用于定义每组包含哪些实际电极
reg [7:0] group_map [0:GROUPS-1][0:ELECTRODES_PER_GROUP-1];

// 电极功能配置数组
// 每组电极的功能配置：
// 00: 收集电位信号
// 01: 发送刺激
// 10: 高阻态
// 11: 保留
reg [1:0] electrode_function [0:GROUPS-1];

// 当前操作的组号和功能配置
reg [3:0] current_group;            // 当前操作的组号 (0-9)
reg [1:0] group_function;           // 当前组的功能配置

// -------------------------------------------------------------------------
// SPI时钟相关信号
// -------------------------------------------------------------------------

reg sclk_prev;                      // 上一时钟周期的SCLK值，用于边沿检测
wire spi_clk_rising_edge = (sclk & ~sclk_prev);   // SCLK上升沿检测信号
wire spi_clk_falling_edge = (~sclk & sclk_prev);  // SCLK下降沿检测信号

// -------------------------------------------------------------------------
// 数据处理模块信号
// -------------------------------------------------------------------------

// 数据输入模块输出信号
wire [DATA_WIDTH-1:0] processed_data [0:CHANNELS-1];  // 经过预处理的RHS芯片数据
wire data_input_valid;                                // 数据输入有效信号
wire data_input_done;                                 // 数据输入完成信号

// 滤波处理模块输出信号
wire [DATA_WIDTH-1:0] filtered_data [0:CHANNELS-1];   // 经过滤波处理的数据
wire filter_data_valid;                               // 滤波数据有效信号
wire [DATA_WIDTH-1:0] spike_count [0:CHANNELS-1];     // 每个通道的尖峰计数
wire processing_done;                                 // 信号处理完成信号

// 数据输出模块信号
wire [CMD_WIDTH-1:0] stim_command;                    // 生成的刺激控制命令
wire command_output_valid;                            // 命令输出有效信号
wire command_output_ready;                            // 命令输出就绪信号
wire output_done;                                     // 输出完成信号

// -------------------------------------------------------------------------
// 刺激控制状态机定义
// -------------------------------------------------------------------------

localparam IDLE        = 4'd0;      // 空闲状态：等待命令
localparam PROCESS     = 4'd1;      // 处理状态：处理命令并生成刺激控制信号
localparam SEND_STIM   = 4'd2;      // 发送刺激状态：发送刺激控制信号
localparam WAIT_STIM   = 4'd3;      // 等待刺激状态：等待刺激控制信号被接收
localparam DONE        = 4'd4;      // 完成状态：传输完成，准备下一次传输

// 时钟边沿检测
always @(posedge clk) begin
    sclk_prev <= sclk;
end

// -------------------------------------------------------------------------
// 电极分组初始化
// 在仿真开始时初始化电极分组映射表和功能配置
// -------------------------------------------------------------------------

integer i, j;  // 循环变量

initial begin
    // -------------------------------------------------------------------------
    // 默认电极分组映射配置
    // 将80个电极分为10组，每组8个电极
    // -------------------------------------------------------------------------
    
    // Group 0: 电极 0-7
    group_map[0][0] = 0; group_map[0][1] = 1; group_map[0][2] = 2; group_map[0][3] = 3;
    group_map[0][4] = 4; group_map[0][5] = 5; group_map[0][6] = 6; group_map[0][7] = 7;
    
    // Group 1: 电极 8-15
    group_map[1][0] = 8; group_map[1][1] = 9; group_map[1][2] = 10; group_map[1][3] = 11;
    group_map[1][4] = 12; group_map[1][5] = 13; group_map[1][6] = 14; group_map[1][7] = 15;
    
    // Group 2: 电极 16-23
    group_map[2][0] = 16; group_map[2][1] = 17; group_map[2][2] = 18; group_map[2][3] = 19;
    group_map[2][4] = 20; group_map[2][5] = 21; group_map[2][6] = 22; group_map[2][7] = 23;
    
    // Group 3: 电极 24-31
    group_map[3][0] = 24; group_map[3][1] = 25; group_map[3][2] = 26; group_map[3][3] = 27;
    group_map[3][4] = 28; group_map[3][5] = 29; group_map[3][6] = 30; group_map[3][7] = 31;
    
    // Group 4: 电极 32-39
    group_map[4][0] = 32; group_map[4][1] = 33; group_map[4][2] = 34; group_map[4][3] = 35;
    group_map[4][4] = 36; group_map[4][5] = 37; group_map[4][6] = 38; group_map[4][7] = 39;
    
    // Group 5: 电极 40-47
    group_map[5][0] = 40; group_map[5][1] = 41; group_map[5][2] = 42; group_map[5][3] = 43;
    group_map[5][4] = 44; group_map[5][5] = 45; group_map[5][6] = 46; group_map[5][7] = 47;
    
    // Group 6: 电极 48-55
    group_map[6][0] = 48; group_map[6][1] = 49; group_map[6][2] = 50; group_map[6][3] = 51;
    group_map[6][4] = 52; group_map[6][5] = 53; group_map[6][6] = 54; group_map[6][7] = 55;
    
    // Group 7: 电极 56-63
    group_map[7][0] = 56; group_map[7][1] = 57; group_map[7][2] = 58; group_map[7][3] = 59;
    group_map[7][4] = 60; group_map[7][5] = 61; group_map[7][6] = 62; group_map[7][7] = 63;
    
    // Group 8: 电极 64-71
    group_map[8][0] = 64; group_map[8][1] = 65; group_map[8][2] = 66; group_map[8][3] = 67;
    group_map[8][4] = 68; group_map[8][5] = 69; group_map[8][6] = 70; group_map[8][7] = 71;
    
    // Group 9: 电极 72-79
    group_map[9][0] = 72; group_map[9][1] = 73; group_map[9][2] = 74; group_map[9][3] = 75;
    group_map[9][4] = 76; group_map[9][5] = 77; group_map[9][6] = 78; group_map[9][7] = 79;
    
    // -------------------------------------------------------------------------
    // 默认功能配置
    // 所有组默认设置为收集信号模式
    // -------------------------------------------------------------------------
    for (i = 0; i < GROUPS; i = i + 1) begin
        electrode_function[i] = 2'b00;  // 默认: 收集信号
    end
    
    // -------------------------------------------------------------------------
    // 默认当前组和功能配置
    // -------------------------------------------------------------------------
    current_group = 4'd0;      // 默认操作第0组
    group_function = 2'b00;    // 默认功能为收集信号
end

// -------------------------------------------------------------------------
// 数据输入模块实例化
// 负责从RHS芯片捕获原始数据并进行预处理
// 根据电极分组配置决定是否捕获特定电极的数据
// -------------------------------------------------------------------------

data_input_module #(
    .DATA_WIDTH(DATA_WIDTH),                    // 数据宽度参数传递
    .CHANNELS(CHANNELS),                        // 通道数量参数传递
    .GROUPS(GROUPS),                            // 电极分组数量参数传递
    .ELECTRODES_PER_GROUP(ELECTRODES_PER_GROUP) // 每组电极数量参数传递
) data_input_inst (
    .clk(clk),                                  // 时钟信号连接
    .reset(reset),                              // 复位信号连接
    .rhs_data_in(rhs_data_in),                  // RHS芯片数据输入连接
    .rhs_data_valid(rhs_data_valid),            // RHS数据有效信号连接
    .group_map(group_map),                      // 电极分组映射表连接
    .electrode_function(electrode_function),    // 电极功能配置连接
    .current_group(current_group),              // 当前操作组号连接
    .processed_data(processed_data),            // 处理后数据输出连接
    .data_out_valid(data_input_valid),          // 数据输出有效信号连接
    .data_capture_en(bypass_enable),            // 数据捕获使能信号连接
    .data_capture_done(data_input_done)         // 数据捕获完成信号连接
);

// -------------------------------------------------------------------------
// 滤波处理模块实例化
// 负责对预处理后的数据进行滤波和尖峰检测
// 根据电极分组配置决定是否对特定电极进行滤波处理
// -------------------------------------------------------------------------

filter_processing_module #(
    .DATA_WIDTH(DATA_WIDTH),                    // 数据宽度参数传递
    .CHANNELS(CHANNELS),                        // 通道数量参数传递
    .GROUPS(GROUPS),                            // 电极分组数量参数传递
    .ELECTRODES_PER_GROUP(ELECTRODES_PER_GROUP) // 每组电极数量参数传递
) filter_inst (
    .clk(clk),                                  // 时钟信号连接
    .reset(reset),                              // 复位信号连接
    .raw_data(processed_data),                  // 原始数据输入连接（来自数据输入模块）
    .data_valid(data_input_valid),              // 数据有效信号连接
    .group_map(group_map),                      // 电极分组映射表连接
    .electrode_function(electrode_function),    // 电极功能配置连接
    .current_group(current_group),              // 当前操作组号连接
    .filter_mode(2'b00),                        // 滤波模式配置 (00:无滤波, 01:高通, 10:低通, 11:带通)
    .threshold(16'h1000),                       // 尖峰检测阈值配置
    .filter_enable(bypass_enable),              // 滤波使能信号连接
    .filtered_data(filtered_data),              // 滤波后数据输出连接
    .data_out_valid(filter_data_valid),         // 滤波数据输出有效信号连接
    .spike_count(spike_count),                  // 尖峰计数输出连接
    .processing_done(processing_done)           // 处理完成信号连接
);

// -------------------------------------------------------------------------
// 数据输出模块实例化
// 负责根据游戏状态和处理结果生成SPI命令
// 支持电极分组配置命令的生成
// -------------------------------------------------------------------------

data_output_module #(
    .DATA_WIDTH(DATA_WIDTH),                    // 数据宽度参数传递
    .CMD_WIDTH(CMD_WIDTH),                      // 命令宽度参数传递
    .CHANNELS(CHANNELS),                        // 通道数量参数传递
    .GROUPS(GROUPS),                            // 电极分组数量参数传递
    .ELECTRODES_PER_GROUP(ELECTRODES_PER_GROUP) // 每组电极数量参数传递
) data_output_inst (
    .clk(clk),                                  // 时钟信号连接
    .reset(reset),                              // 复位信号连接
    .ball_x(ball_x),                            // 游戏球X坐标输入连接
    .ball_y(ball_y),                            // 游戏球Y坐标输入连接
    .win_counter(win_counter),                  // 获胜计数器输入连接
    .lose_counter(lose_counter),                // 失败计数器输入连接
    .game_result(game_result),                  // 游戏结果输入连接
    .result_en(result_en),                      // 结果使能信号输入连接
    .spike_count(spike_count),                  // 尖峰计数输入连接（来自滤波处理模块）
    .spike_data_valid(filter_data_valid),       // 尖峰数据有效信号连接
    .current_group(current_group),              // 当前操作组号连接
    .group_function(group_function),            // 当前组功能配置连接
    .game_mode(game_mode),                      // 游戏模式选择输入连接
    .output_enable(bypass_enable),              // 输出使能信号连接
    .spi_command(spi_command),                  // 生成的SPI命令输出连接
    .command_valid(command_output_valid),       // 命令输出有效信号连接
    .command_ready(command_output_ready),       // 命令输出就绪信号连接
    .output_done(output_done)                   // 输出完成信号连接
);

// -------------------------------------------------------------------------
// 游戏模块接口连接（简化实现）
// 当前版本为简化实现，后续可扩展完整的游戏逻辑
// -------------------------------------------------------------------------

assign game_start_ready = 1'b1;      // 游戏开始准备就绪信号（始终准备就绪）
assign game_end_ready = 1'b1;       // 游戏结束准备就绪信号（始终准备就绪）
assign result_en = 1'b0;            // 结果使能信号（当前版本未启用）
assign game_result = 1'b0;          // 游戏结果信号（当前版本固定为0）
assign ball_x = 8'h00;              // 游戏球X坐标（当前版本固定为0）
assign ball_y = 8'h00;              // 游戏球Y坐标（当前版本固定为0）

// -------------------------------------------------------------------------
// 命令寄存器 - 存储待发送的命令
// 负责存储来自上位机或内部模块生成的待发送命令
// 同时处理电极分组配置命令
// -------------------------------------------------------------------------

always @(posedge clk or posedge reset) begin
    if (reset) begin
        command_reg <= 32'h00000000;        // 命令寄存器复位
        command_reg_valid <= 1'b0;          // 命令寄存器有效标志复位
    end else begin
        if (command_valid && bypass_enable) begin
            command_reg <= command_data;    // 存储来自上位机的命令数据
            command_reg_valid <= 1'b1;      // 设置命令有效标志
            
            // Command structure for electrode grouping configuration:
            // - Bits [31:28]: Command identifier (4'b0001 for electrode grouping)
            // - Bits [27:24]: Group number (0-9, corresponding to 10 groups)
            // - Bits [23:22]: Function selection (00: collect signal, 01: send stimulation, 10: high impedance)
            // - Bits [21:0]: Reserved for future use
            // ---------------------------------------------------------------------
            // 电极分组配置命令处理
            // 指令格式: [31:28] = 4'b0001 (电极分组配置命令标识)
            //          [27:24] = 组号 (0-9)
            //          [23:22] = 功能选择 (00:收集信号, 01:发送刺激, 10:高阻态)
            //          [21:0]  = 保留位
            // ---------------------------------------------------------------------
            if (command_data[31:28] == 4'b0001) begin
                current_group <= command_data[27:24];      // 提取并更新当前操作组号
                group_function <= command_data[23:22];     // 提取并更新组功能配置
                
                // 检查组号有效性并更新电极功能配置
                if (command_data[27:24] < GROUPS) begin
                    electrode_function[command_data[27:24]] <= command_data[23:22];
                end
            end
        end else if (command_output_valid) begin
            command_reg <= stim_command;                   // 存储来自数据输出模块的命令
            command_reg_valid <= 1'b1;                      // 设置命令有效标志
        end else if (state == DONE) begin
            command_reg_valid <= 1'b0;                      // 清除命令有效标志
        end
    end
end

// -------------------------------------------------------------------------
// 主状态机 - 控制刺激信号生成流程
// 负责管理刺激控制信号的完整时序，包括命令处理和信号发送
// -------------------------------------------------------------------------

always @(posedge clk or posedge reset) begin
    if (reset) begin
        state <= IDLE;              // 复位时进入空闲状态
    end else begin
        state <= next_state;        // 根据下一状态更新当前状态
    end
end

// -------------------------------------------------------------------------
// 状态转移逻辑 - 定义刺激控制状态机的状态转换规则
// -------------------------------------------------------------------------

always @(*) begin
    case (state)
        // ---------------------------------------------------------------------
        // IDLE状态 - 空闲状态
        // 等待有效的命令数据准备处理
        // ---------------------------------------------------------------------
        IDLE: begin
            if (command_reg_valid && bypass_enable)
                next_state = PROCESS;        // 有有效命令时转到处理状态
            else
                next_state = IDLE;           // 否则继续保持空闲状态
        end
        
        // ---------------------------------------------------------------------
        // PROCESS状态 - 命令处理状态
        // 处理命令并生成相应的刺激控制信号
        // ---------------------------------------------------------------------
        PROCESS: begin
            next_state = SEND_STIM;          // 处理完成后转到发送刺激状态
        end
        
        // ---------------------------------------------------------------------
        // SEND_STIM状态 - 发送刺激状态
        // 发送刺激控制信号到刺激序列器
        // ---------------------------------------------------------------------
        SEND_STIM: begin
            next_state = WAIT_STIM;          // 发送后转到等待状态
        end
        
        // ---------------------------------------------------------------------
        // WAIT_STIM状态 - 等待刺激状态
        // 等待刺激控制信号被接收
        // ---------------------------------------------------------------------
        WAIT_STIM: begin
            if (stim_cmd_ready)
                next_state = DONE;           // 刺激命令被接收后转到完成状态
            else
                next_state = WAIT_STIM;      // 否则继续等待
        end
        
        // ---------------------------------------------------------------------
        // DONE状态 - 完成状态
        // 标记刺激控制信号发送完成，准备下一次传输
        // ---------------------------------------------------------------------
        DONE: begin
            next_state = IDLE;               // 返回空闲状态等待下一次传输
        end
        
        // ---------------------------------------------------------------------
        // 默认状态处理
        // ---------------------------------------------------------------------
        default: next_state = IDLE;          // 异常情况下返回空闲状态
    endcase
end

// -------------------------------------------------------------------------
// 状态机输出和数据处理 - 根据当前状态执行具体的刺激控制操作
// 包括命令处理、刺激信号生成和响应处理
// -------------------------------------------------------------------------

always @(posedge clk or posedge reset) begin
    if (reset) begin
        // ---------------------------------------------------------------------
        // 复位状态下初始化所有输出信号
        // ---------------------------------------------------------------------
        stim_cmd_valid <= 1'b0;                 // 刺激命令有效信号初始化为无效
        stim_channel <= 6'd0;                   // 刺激通道初始化为0
        stim_shutdown <= 1'b0;                  // 安全关闭信号初始化为无效
        // Initialize all channel control signals
        stim_on_A1 <= 16'h0000;                 // A1通道刺激开启控制初始化为全关闭
        stim_pol_A1 <= 16'h0000;                // A1通道刺激极性控制初始化为默认极性
        stim_amp_settle_A1 <= 16'h0000;         // A1通道放大器稳定控制初始化为关闭
        stim_charge_recov_A1 <= 16'h0000;       // A1通道电荷恢复控制初始化为关闭
        stim_on_A2 <= 16'h0000;                 // A2通道刺激开启控制初始化为全关闭
        stim_pol_A2 <= 16'h0000;                // A2通道刺激极性控制初始化为默认极性
        stim_amp_settle_A2 <= 16'h0000;         // A2通道放大器稳定控制初始化为关闭
        stim_charge_recov_A2 <= 16'h0000;       // A2通道电荷恢复控制初始化为关闭
        stim_on_B1 <= 16'h0000;                 // B1通道刺激开启控制初始化为全关闭
        stim_pol_B1 <= 16'h0000;                // B1通道刺激极性控制初始化为默认极性
        stim_amp_settle_B1 <= 16'h0000;         // B1通道放大器稳定控制初始化为关闭
        stim_charge_recov_B1 <= 16'h0000;       // B1通道电荷恢复控制初始化为关闭
        stim_on_B2 <= 16'h0000;                 // B2通道刺激开启控制初始化为全关闭
        stim_pol_B2 <= 16'h0000;                // B2通道刺激极性控制初始化为默认极性
        stim_amp_settle_B2 <= 16'h0000;         // B2通道放大器稳定控制初始化为关闭
        stim_charge_recov_B2 <= 16'h0000;       // B2通道电荷恢复控制初始化为关闭
        stim_on_C1 <= 16'h0000;                 // C1通道刺激开启控制初始化为全关闭
        stim_pol_C1 <= 16'h0000;                // C1通道刺激极性控制初始化为默认极性
        stim_amp_settle_C1 <= 16'h0000;         // C1通道放大器稳定控制初始化为关闭
        stim_charge_recov_C1 <= 16'h0000;       // C1通道电荷恢复控制初始化为关闭
        stim_on_C2 <= 16'h0000;                 // C2通道刺激开启控制初始化为全关闭
        stim_pol_C2 <= 16'h0000;                // C2通道刺激极性控制初始化为默认极性
        stim_amp_settle_C2 <= 16'h0000;         // C2通道放大器稳定控制初始化为关闭
        stim_charge_recov_C2 <= 16'h0000;       // C2通道电荷恢复控制初始化为关闭
        stim_on_D1 <= 16'h0000;                 // D1通道刺激开启控制初始化为全关闭
        stim_pol_D1 <= 16'h0000;                // D1通道刺激极性控制初始化为默认极性
        stim_amp_settle_D1 <= 16'h0000;         // D1通道放大器稳定控制初始化为关闭
        stim_charge_recov_D1 <= 16'h0000;       // D1通道电荷恢复控制初始化为关闭
        stim_on_D2 <= 16'h0000;                 // D2通道刺激开启控制初始化为全关闭
        stim_pol_D2 <= 16'h0000;                // D2通道刺激极性控制初始化为默认极性
        stim_amp_settle_D2 <= 16'h0000;         // D2通道放大器稳定控制初始化为关闭
        stim_charge_recov_D2 <= 16'h0000;       // D2通道电荷恢复控制初始化为关闭
        stim_amp_settle_changed <= 1'b0;        // 放大器稳定控制改变信号初始化为无变化
        response_data <= 32'h00000000;          // 响应数据寄存器清零
        response_valid <= 1'b0;                 // 响应数据有效标志清零
        busy <= 1'b0;                           // 忙信号清零
        win_counter <= 8'h00;                   // 获胜计数器清零
        lose_counter <= 8'h00;                  // 失败计数器清零
        command_processed <= 1'b0;              // 命令处理完成标志初始化为未完成
        cmd_delay_counter <= 4'd0;             // 命令延迟计数器初始化为0
        
        // ---------------------------------------------------------------------
        // 重置电极分组配置为默认值
        // ---------------------------------------------------------------------
        integer i, j;
        for (i = 0; i < GROUPS; i = i + 1) begin
            electrode_function[i] <= 2'b00;     // 默认: 收集信号
        end
        current_group <= 4'd0;                  // 当前组号重置为0
        group_function <= 2'b00;                // 当前组功能重置为收集信号
    end else begin
        case (state)
            // ---------------------------------------------------------------------
            // IDLE状态 - 空闲状态处理
            // 准备接收新的命令并维持刺激接口处于适当状态
            // ---------------------------------------------------------------------
            IDLE: begin
                stim_cmd_valid <= 1'b0;                 // 清除刺激命令有效标志
                response_valid <= 1'b0;                 // 清除响应有效标志
                busy <= 1'b0;                           // 清除忙标志
                command_processed <= 1'b0;              // 清除命令处理完成标志
                cmd_delay_counter <= 4'd0;             // 延迟计数器清零
            end
            
            // ---------------------------------------------------------------------
            // PROCESS状态 - 命令处理状态处理
            // 处理命令并生成相应的刺激控制信号
            // ---------------------------------------------------------------------
            PROCESS: begin
                stim_cmd_valid <= 1'b0;                 // 初始化刺激命令有效标志
                response_valid <= 1'b0;                 // 清除响应有效标志
                busy <= 1'b1;                           // 设置忙标志表示正在进行处理
                command_processed <= 1'b0;              // 初始化命令处理完成标志
                
                // 根据命令类型生成相应的刺激控制信号
                case (command_reg[31:28])
                    // 电极分组配置命令 (0001)
                    4'b0001: begin
                        stim_channel <= 6'd16;              // 使用刺激通道16发送分组配置
                        stim_shutdown <= 1'b0;              // 不关闭系统
                        // 根据组功能设置刺激控制信号 - 应用于所有通道
                        case (command_reg[23:22])
                            2'b00: begin  // 收集信号模式
                                // 关闭所有刺激
                                stim_on_A1 <= 16'h0000; stim_on_A2 <= 16'h0000;
                                stim_on_B1 <= 16'h0000; stim_on_B2 <= 16'h0000;
                                stim_on_C1 <= 16'h0000; stim_on_C2 <= 16'h0000;
                                stim_on_D1 <= 16'h0000; stim_on_D2 <= 16'h0000;
                                // 默认极性
                                stim_pol_A1 <= 16'h0000; stim_pol_A2 <= 16'h0000;
                                stim_pol_B1 <= 16'h0000; stim_pol_B2 <= 16'h0000;
                                stim_pol_C1 <= 16'h0000; stim_pol_C2 <= 16'h0000;
                                stim_pol_D1 <= 16'h0000; stim_pol_D2 <= 16'h0000;
                                // 关闭电荷恢复
                                stim_charge_recov_A1 <= 16'h0000; stim_charge_recov_A2 <= 16'h0000;
                                stim_charge_recov_B1 <= 16'h0000; stim_charge_recov_B2 <= 16'h0000;
                                stim_charge_recov_C1 <= 16'h0000; stim_charge_recov_C2 <= 16'h0000;
                                stim_charge_recov_D1 <= 16'h0000; stim_charge_recov_D2 <= 16'h0000;
                                // 关闭放大器稳定
                                stim_amp_settle_A1 <= 16'h0000; stim_amp_settle_A2 <= 16'h0000;
                                stim_amp_settle_B1 <= 16'h0000; stim_amp_settle_B2 <= 16'h0000;
                                stim_amp_settle_C1 <= 16'h0000; stim_amp_settle_C2 <= 16'h0000;
                                stim_amp_settle_D1 <= 16'h0000; stim_amp_settle_D2 <= 16'h0000;
                            end
                            2'b01: begin  // 发送刺激模式
                                // 开启所有刺激
                                stim_on_A1 <= 16'hFFFF; stim_on_A2 <= 16'hFFFF;
                                stim_on_B1 <= 16'hFFFF; stim_on_B2 <= 16'hFFFF;
                                stim_on_C1 <= 16'hFFFF; stim_on_C2 <= 16'hFFFF;
                                stim_on_D1 <= 16'hFFFF; stim_on_D2 <= 16'hFFFF;
                                // 默认极性
                                stim_pol_A1 <= 16'h0000; stim_pol_A2 <= 16'h0000;
                                stim_pol_B1 <= 16'h0000; stim_pol_B2 <= 16'h0000;
                                stim_pol_C1 <= 16'h0000; stim_pol_C2 <= 16'h0000;
                                stim_pol_D1 <= 16'h0000; stim_pol_D2 <= 16'h0000;
                                // 开启电荷恢复
                                stim_charge_recov_A1 <= 16'hFFFF; stim_charge_recov_A2 <= 16'hFFFF;
                                stim_charge_recov_B1 <= 16'hFFFF; stim_charge_recov_B2 <= 16'hFFFF;
                                stim_charge_recov_C1 <= 16'hFFFF; stim_charge_recov_C2 <= 16'hFFFF;
                                stim_charge_recov_D1 <= 16'hFFFF; stim_charge_recov_D2 <= 16'hFFFF;
                                // 开启放大器稳定
                                stim_amp_settle_A1 <= 16'hFFFF; stim_amp_settle_A2 <= 16'hFFFF;
                                stim_amp_settle_B1 <= 16'hFFFF; stim_amp_settle_B2 <= 16'hFFFF;
                                stim_amp_settle_C1 <= 16'hFFFF; stim_amp_settle_C2 <= 16'hFFFF;
                                stim_amp_settle_D1 <= 16'hFFFF; stim_amp_settle_D2 <= 16'hFFFF;
                            end
                            2'b10: begin  // 高阻态模式
                                // 关闭所有刺激
                                stim_on_A1 <= 16'h0000; stim_on_A2 <= 16'h0000;
                                stim_on_B1 <= 16'h0000; stim_on_B2 <= 16'h0000;
                                stim_on_C1 <= 16'h0000; stim_on_C2 <= 16'h0000;
                                stim_on_D1 <= 16'h0000; stim_on_D2 <= 16'h0000;
                                // 默认极性
                                stim_pol_A1 <= 16'h0000; stim_pol_A2 <= 16'h0000;
                                stim_pol_B1 <= 16'h0000; stim_pol_B2 <= 16'h0000;
                                stim_pol_C1 <= 16'h0000; stim_pol_C2 <= 16'h0000;
                                stim_pol_D1 <= 16'h0000; stim_pol_D2 <= 16'h0000;
                                // 关闭电荷恢复
                                stim_charge_recov_A1 <= 16'h0000; stim_charge_recov_A2 <= 16'h0000;
                                stim_charge_recov_B1 <= 16'h0000; stim_charge_recov_B2 <= 16'h0000;
                                stim_charge_recov_C1 <= 16'h0000; stim_charge_recov_C2 <= 16'h0000;
                                stim_charge_recov_D1 <= 16'h0000; stim_charge_recov_D2 <= 16'h0000;
                                // 关闭放大器稳定
                                stim_amp_settle_A1 <= 16'h0000; stim_amp_settle_A2 <= 16'h0000;
                                stim_amp_settle_B1 <= 16'h0000; stim_amp_settle_B2 <= 16'h0000;
                                stim_amp_settle_C1 <= 16'h0000; stim_amp_settle_C2 <= 16'h0000;
                                stim_amp_settle_D1 <= 16'h0000; stim_amp_settle_D2 <= 16'h0000;
                            end
                            default: begin
                                // 默认关闭
                                stim_on_A1 <= 16'h0000; stim_on_A2 <= 16'h0000;
                                stim_on_B1 <= 16'h0000; stim_on_B2 <= 16'h0000;
                                stim_on_C1 <= 16'h0000; stim_on_C2 <= 16'h0000;
                                stim_on_D1 <= 16'h0000; stim_on_D2 <= 16'h0000;
                                // 默认极性
                                stim_pol_A1 <= 16'h0000; stim_pol_A2 <= 16'h0000;
                                stim_pol_B1 <= 16'h0000; stim_pol_B2 <= 16'h0000;
                                stim_pol_C1 <= 16'h0000; stim_pol_C2 <= 16'h0000;
                                stim_pol_D1 <= 16'h0000; stim_pol_D2 <= 16'h0000;
                                // 关闭电荷恢复
                                stim_charge_recov_A1 <= 16'h0000; stim_charge_recov_A2 <= 16'h0000;
                                stim_charge_recov_B1 <= 16'h0000; stim_charge_recov_B2 <= 16'h0000;
                                stim_charge_recov_C1 <= 16'h0000; stim_charge_recov_C2 <= 16'h0000;
                                stim_charge_recov_D1 <= 16'h0000; stim_charge_recov_D2 <= 16'h0000;
                                // 关闭放大器稳定
                                stim_amp_settle_A1 <= 16'h0000; stim_amp_settle_A2 <= 16'h0000;
                                stim_amp_settle_B1 <= 16'h0000; stim_amp_settle_B2 <= 16'h0000;
                                stim_amp_settle_C1 <= 16'h0000; stim_amp_settle_C2 <= 16'h0000;
                                stim_amp_settle_D1 <= 16'h0000; stim_amp_settle_D2 <= 16'h0000;
                            end
                        endcase
                        stim_amp_settle_changed <= 1'b1;    // 标记放大器设置已改变
                    end
                    
                    // 游戏数据命令 (0002)
                    4'b0010: begin
                        stim_channel <= 6'd17;              // 使用刺激通道17发送游戏数据
                        stim_shutdown <= 1'b0;              // 不关闭系统
                        // 关闭刺激
                        stim_on_A1 <= 16'h0000; stim_on_A2 <= 16'h0000;
                        stim_on_B1 <= 16'h0000; stim_on_B2 <= 16'h0000;
                        stim_on_C1 <= 16'h0000; stim_on_C2 <= 16'h0000;
                        stim_on_D1 <= 16'h0000; stim_on_D2 <= 16'h0000;
                        // 默认极性
                        stim_pol_A1 <= 16'h0000; stim_pol_A2 <= 16'h0000;
                        stim_pol_B1 <= 16'h0000; stim_pol_B2 <= 16'h0000;
                        stim_pol_C1 <= 16'h0000; stim_pol_C2 <= 16'h0000;
                        stim_pol_D1 <= 16'h0000; stim_pol_D2 <= 16'h0000;
                        // 关闭电荷恢复
                        stim_charge_recov_A1 <= 16'h0000; stim_charge_recov_A2 <= 16'h0000;
                        stim_charge_recov_B1 <= 16'h0000; stim_charge_recov_B2 <= 16'h0000;
                        stim_charge_recov_C1 <= 16'h0000; stim_charge_recov_C2 <= 16'h0000;
                        stim_charge_recov_D1 <= 16'h0000; stim_charge_recov_D2 <= 16'h0000;
                        // 关闭放大器稳定
                        stim_amp_settle_A1 <= 16'h0000; stim_amp_settle_A2 <= 16'h0000;
                        stim_amp_settle_B1 <= 16'h0000; stim_amp_settle_B2 <= 16'h0000;
                        stim_amp_settle_C1 <= 16'h0000; stim_amp_settle_C2 <= 16'h0000;
                        stim_amp_settle_D1 <= 16'h0000; stim_amp_settle_D2 <= 16'h0000;
                        stim_amp_settle_changed <= 1'b0;    // 无放大器设置改变
                    end
                    
                    // 神经尖峰数据命令 (0010)
                    4'b0011: begin
                        stim_channel <= 6'd18;              // 使用刺激通道18发送尖峰数据
                        stim_shutdown <= 1'b0;              // 不关闭系统
                        // 关闭刺激
                        stim_on_A1 <= 16'h0000; stim_on_A2 <= 16'h0000;
                        stim_on_B1 <= 16'h0000; stim_on_B2 <= 16'h0000;
                        stim_on_C1 <= 16'h0000; stim_on_C2 <= 16'h0000;
                        stim_on_D1 <= 16'h0000; stim_on_D2 <= 16'h0000;
                        // 默认极性
                        stim_pol_A1 <= 16'h0000; stim_pol_A2 <= 16'h0000;
                        stim_pol_B1 <= 16'h0000; stim_pol_B2 <= 16'h0000;
                        stim_pol_C1 <= 16'h0000; stim_pol_C2 <= 16'h0000;
                        stim_pol_D1 <= 16'h0000; stim_pol_D2 <= 16'h0000;
                        // 关闭电荷恢复
                        stim_charge_recov_A1 <= 16'h0000; stim_charge_recov_A2 <= 16'h0000;
                        stim_charge_recov_B1 <= 16'h0000; stim_charge_recov_B2 <= 16'h0000;
                        stim_charge_recov_C1 <= 16'h0000; stim_charge_recov_C2 <= 16'h0000;
                        stim_charge_recov_D1 <= 16'h0000; stim_charge_recov_D2 <= 16'h0000;
                        // 关闭放大器稳定
                        stim_amp_settle_A1 <= 16'h0000; stim_amp_settle_A2 <= 16'h0000;
                        stim_amp_settle_B1 <= 16'h0000; stim_amp_settle_B2 <= 16'h0000;
                        stim_amp_settle_C1 <= 16'h0000; stim_amp_settle_C2 <= 16'h0000;
                        stim_amp_settle_D1 <= 16'h0000; stim_amp_settle_D2 <= 16'h0000;
                        stim_amp_settle_changed <= 1'b0;    // 无放大器设置改变
                    end
                    
                    // 控制命令 (0011)
                    4'b0100: begin
                        stim_channel <= 6'd19;              // 使用刺激通道19发送控制数据
                        stim_shutdown <= 1'b0;              // 不关闭系统
                        // 关闭刺激
                        stim_on_A1 <= 16'h0000; stim_on_A2 <= 16'h0000;
                        stim_on_B1 <= 16'h0000; stim_on_B2 <= 16'h0000;
                        stim_on_C1 <= 16'h0000; stim_on_C2 <= 16'h0000;
                        stim_on_D1 <= 16'h0000; stim_on_D2 <= 16'h0000;
                        // 默认极性
                        stim_pol_A1 <= 16'h0000; stim_pol_A2 <= 16'h0000;
                        stim_pol_B1 <= 16'h0000; stim_pol_B2 <= 16'h0000;
                        stim_pol_C1 <= 16'h0000; stim_pol_C2 <= 16'h0000;
                        stim_pol_D1 <= 16'h0000; stim_pol_D2 <= 16'h0000;
                        // 关闭电荷恢复
                        stim_charge_recov_A1 <= 16'h0000; stim_charge_recov_A2 <= 16'h0000;
                        stim_charge_recov_B1 <= 16'h0000; stim_charge_recov_B2 <= 16'h0000;
                        stim_charge_recov_C1 <= 16'h0000; stim_charge_recov_C2 <= 16'h0000;
                        stim_charge_recov_D1 <= 16'h0000; stim_charge_recov_D2 <= 16'h0000;
                        // 关闭放大器稳定
                        stim_amp_settle_A1 <= 16'h0000; stim_amp_settle_A2 <= 16'h0000;
                        stim_amp_settle_B1 <= 16'h0000; stim_amp_settle_B2 <= 16'h0000;
                        stim_amp_settle_C1 <= 16'h0000; stim_amp_settle_C2 <= 16'h0000;
                        stim_amp_settle_D1 <= 16'h0000; stim_amp_settle_D2 <= 16'h0000;
                        stim_amp_settle_changed <= 1'b0;    // 无放大器设置改变
                    end
                    
                    // 默认情况 - 安全关闭
                    default: begin
                        stim_channel <= 6'd0;               // 使用通道0
                        stim_shutdown <= 1'b1;              // 安全关闭系统
                        // 关闭所有刺激
                        stim_on_A1 <= 16'h0000; stim_on_A2 <= 16'h0000;
                        stim_on_B1 <= 16'h0000; stim_on_B2 <= 16'h0000;
                        stim_on_C1 <= 16'h0000; stim_on_C2 <= 16'h0000;
                        stim_on_D1 <= 16'h0000; stim_on_D2 <= 16'h0000;
                        // 默认极性
                        stim_pol_A1 <= 16'h0000; stim_pol_A2 <= 16'h0000;
                        stim_pol_B1 <= 16'h0000; stim_pol_B2 <= 16'h0000;
                        stim_pol_C1 <= 16'h0000; stim_pol_C2 <= 16'h0000;
                        stim_pol_D1 <= 16'h0000; stim_pol_D2 <= 16'h0000;
                        // 关闭电荷恢复
                        stim_charge_recov_A1 <= 16'h0000; stim_charge_recov_A2 <= 16'h0000;
                        stim_charge_recov_B1 <= 16'h0000; stim_charge_recov_B2 <= 16'h0000;
                        stim_charge_recov_C1 <= 16'h0000; stim_charge_recov_C2 <= 16'h0000;
                        stim_charge_recov_D1 <= 16'h0000; stim_charge_recov_D2 <= 16'h0000;
                        // 关闭放大器稳定
                        stim_amp_settle_A1 <= 16'h0000; stim_amp_settle_A2 <= 16'h0000;
                        stim_amp_settle_B1 <= 16'h0000; stim_amp_settle_B2 <= 16'h0000;
                        stim_amp_settle_C1 <= 16'h0000; stim_amp_settle_C2 <= 16'h0000;
                        stim_amp_settle_D1 <= 16'h0000; stim_amp_settle_D2 <= 16'h0000;
                        stim_amp_settle_changed <= 1'b0;    // 无放大器设置改变
                    end
                endcase
                
                command_processed <= 1'b1;              // 标记命令处理完成
            end
            
            // ---------------------------------------------------------------------
            // SEND_STIM状态 - 发送刺激状态处理
            // 发送刺激控制信号到刺激序列器
            // ---------------------------------------------------------------------
            SEND_STIM: begin
                stim_cmd_valid <= 1'b1;                 // 设置刺激命令有效标志
                response_valid <= 1'b0;                 // 清除响应有效标志
                busy <= 1'b1;                           // 保持忙标志
                command_processed <= 1'b1;              // 保持命令处理完成标志
                
                // 设置延迟计数器以确保信号稳定
                cmd_delay_counter <= 4'd2;              // 设置短暂延迟
            end
            
            // ---------------------------------------------------------------------
            // WAIT_STIM状态 - 等待刺激状态处理
            // 等待刺激控制信号被接收
            // ---------------------------------------------------------------------
            WAIT_STIM: begin
                if (cmd_delay_counter > 4'd0) begin
                    cmd_delay_counter <= cmd_delay_counter - 1;   // 延迟计数器递减
                end else begin
                    stim_cmd_valid <= 1'b0;             // 延迟结束后清除刺激命令有效标志
                end
                response_valid <= 1'b0;                 // 清除响应有效标志
                busy <= 1'b1;                           // 保持忙标志
                command_processed <= 1'b1;              // 保持命令处理完成标志
            end
            
            // ---------------------------------------------------------------------
            // DONE状态 - 完成状态处理
            // 清理状态并准备下一次传输
            // ---------------------------------------------------------------------
            DONE: begin
                stim_cmd_valid <= 1'b0;                 // 清除刺激命令有效标志
                response_valid <= 1'b1;                 // 设置响应数据有效标志
                busy <= 1'b0;                           // 清除忙标志
                command_processed <= 1'b0;              // 清除命令处理完成标志
                cmd_delay_counter <= 4'd0;             // 清零延迟计数器
                
                // 设置响应数据为处理后的命令
                response_data <= {command_reg[31:4], 4'h0};  // 返回处理过的命令数据
                
                // 更新胜负计数器
                if (command_reg[31]) begin
                    win_counter <= win_counter + 1;     // 最高位为1表示获胜
                end else begin
                    lose_counter <= lose_counter + 1;   // 最高位为0表示失败
                end
            end
        endcase
    end
end

endmodule