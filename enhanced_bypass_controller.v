`timescale 1ns/1ps

// =============================================================================
// 模块名称: enhanced_bypass_controller
// 描述:    增强型旁路控制器，支持电极分组功能
//          该模块实现了独立的SPI通信控制，用于与下级设备通信
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
    // SPI接口 - 连接到主SPI总线
    // -------------------------------------------------------------------------
    output reg cs_n,                    // 片选信号 (低电平有效)
    output reg sclk,                    // SPI时钟信号
    output reg mosi,                    // 主出从入数据线 (Master Out Slave In)
    input wire miso                     // 主入从出数据线 (Master In Slave Out)
);

// -------------------------------------------------------------------------
// 内部信号定义
// -------------------------------------------------------------------------

// SPI通信状态机信号
reg [3:0] state, next_state;        // 当前状态和下一状态寄存器
reg [31:0] shift_reg;               // 移位寄存器，用于接收SPI数据
reg [4:0] bit_count;                // 位计数器，跟踪已传输的位数
reg [3:0] delay_counter;            // 延迟计数器，用于SPI时序控制
reg [31:0] command_reg;             // 命令寄存器，存储待发送的命令
reg command_reg_valid;              // 命令寄存器有效标志

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
wire [CMD_WIDTH-1:0] spi_command;                     // 生成的SPI命令
wire command_output_valid;                            // 命令输出有效信号
wire command_output_ready;                            // 命令输出就绪信号
wire output_done;                                     // 输出完成信号

// -------------------------------------------------------------------------
// SPI通信状态机定义
// -------------------------------------------------------------------------

localparam IDLE        = 4'd0;      // 空闲状态：等待命令
localparam CS_ASSERT   = 4'd1;      // 片选拉低状态：拉低CS_N信号
localparam TRANSFER    = 4'd2;      // 数据传输状态：进行SPI数据传输
localparam CS_DEASSERT = 4'd3;      // 片选拉高状态：拉高CS_N信号
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
            command_reg <= spi_command;                    // 存储来自数据输出模块的命令
            command_reg_valid <= 1'b1;                      // 设置命令有效标志
        end else if (state == DONE) begin
            command_reg_valid <= 1'b0;                      // 清除命令有效标志
        end
    end
end

// -------------------------------------------------------------------------
// 主状态机 - 控制SPI通信流程
// 负责管理SPI传输的完整时序，包括片选控制和数据传输
// -------------------------------------------------------------------------

always @(posedge clk or posedge reset) begin
    if (reset) begin
        state <= IDLE;              // 复位时进入空闲状态
    end else begin
        state <= next_state;        // 根据下一状态更新当前状态
    end
end

// -------------------------------------------------------------------------
// 状态转移逻辑 - 定义SPI通信状态机的状态转换规则
// -------------------------------------------------------------------------

always @(*) begin
    case (state)
        // ---------------------------------------------------------------------
        // IDLE状态 - 空闲状态
        // 等待有效的命令数据准备传输
        // ---------------------------------------------------------------------
        IDLE: begin
            if (command_reg_valid && bypass_enable)
                next_state = CS_ASSERT;     // 有有效命令时转到片选拉低状态
            else
                next_state = IDLE;           // 否则继续保持空闲状态
        end
        
        // ---------------------------------------------------------------------
        // CS_ASSERT状态 - 片选拉低状态
        // 拉低CS_N信号以启动SPI传输
        // ---------------------------------------------------------------------
        CS_ASSERT: begin
            next_state = TRANSFER;           // 直接转到数据传输状态
        end
        
        // ---------------------------------------------------------------------
        // TRANSFER状态 - 数据传输状态
        // 执行32位SPI数据的逐位传输
        // ---------------------------------------------------------------------
        TRANSFER: begin
            if (bit_count == 5'd32)
                next_state = CS_DEASSERT;    // 传输完32位后转到片选拉高状态
            else
                next_state = TRANSFER;       // 否则继续数据传输
        end
        
        // ---------------------------------------------------------------------
        // CS_DEASSERT状态 - 片选拉高状态
        // 拉高CS_N信号以结束SPI传输
        // ---------------------------------------------------------------------
        CS_DEASSERT: begin
            next_state = DONE;               // 转到完成状态
        end
        
        // ---------------------------------------------------------------------
        // DONE状态 - 完成状态
        // 标记SPI传输完成，准备下一次传输
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
// 状态机输出和数据处理 - 根据当前状态执行具体的SPI操作
// 包括片选控制、时钟生成、数据传输和响应处理
// -------------------------------------------------------------------------

always @(posedge clk or posedge reset) begin
    if (reset) begin
        // ---------------------------------------------------------------------
        // 复位状态下初始化所有输出信号
        // ---------------------------------------------------------------------
        cs_n <= 1'b1;                           // 片选信号初始化为高电平（非选中）
        sclk <= 1'b0;                           // 时钟信号初始化为低电平
        mosi <= 1'b0;                           // 数据输出初始化为低电平
        shift_reg <= 32'h00000000;              // 移位寄存器清零
        bit_count <= 5'd0;                      // 位计数器清零
        delay_counter <= 4'd0;                 // 延迟计数器清零
        response_data <= 32'h00000000;          // 响应数据寄存器清零
        response_valid <= 1'b0;                 // 响应数据有效标志清零
        busy <= 1'b0;                           // 忙信号清零
        win_counter <= 8'h00;                   // 获胜计数器清零
        lose_counter <= 8'h00;                  // 失败计数器清零
        
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
            // 准备接收新的命令并维持SPI接口处于适当状态
            // ---------------------------------------------------------------------
            IDLE: begin
                cs_n <= auto_cs_n ? manual_cs_n : 1'b1;  // 根据自动/手动控制设置CS_N
                sclk <= (spi_mode == 2'b10) || (spi_mode == 2'b11);  // 模式2和3时SCLK初始为高
                mosi <= 1'b0;                           // MOSI保持低电平
                shift_reg <= 32'h00000000;              // 清空移位寄存器
                bit_count <= 5'd0;                      // 位计数器清零
                delay_counter <= 4'd0;                 // 延迟计数器清零
                response_valid <= 1'b0;                 // 清除响应有效标志
                busy <= 1'b0;                           // 清除忙标志
            end
            
            // ---------------------------------------------------------------------
            // CS_ASSERT状态 - 片选拉低状态处理
            // 拉低CS_N信号以启动SPI传输，并准备发送第一个数据位
            // ---------------------------------------------------------------------
            CS_ASSERT: begin
                cs_n <= 1'b0;                           // 拉低CS_N信号启动传输
                sclk <= (spi_mode == 2'b10) || (spi_mode == 2'b11);  // 根据SPI模式设置SCLK初始状态
                mosi <= command_reg[31];                 // 输出命令数据的最高位
                shift_reg <= 32'h00000000;              // 清空移位寄存器用于接收响应
                bit_count <= 5'd0;                      // 位计数器初始化
                delay_counter <= 4'd2;                  // 设置短暂延迟以满足时序要求
                response_valid <= 1'b0;                 // 清除响应有效标志
                busy <= 1'b1;                           // 设置忙标志表示正在进行传输
            end
            
            // ---------------------------------------------------------------------
            // TRANSFER状态 - 数据传输状态处理
            // 执行32位SPI数据的逐位传输，包括发送命令和接收响应
            // ---------------------------------------------------------------------
            TRANSFER: begin
                if (delay_counter > 4'd0) begin
                    delay_counter <= delay_counter - 1;   // 延迟计数器递减
                end else begin
                    // -----------------------------------------------------------------
                    // SPI mode timing characteristics:
                    // - Mode 0 (CPOL=0, CPHA=0): Clock idle low, sample on rising edge, setup on falling edge
                    // - Mode 1 (CPOL=0, CPHA=1): Clock idle low, sample on falling edge, setup on rising edge
                    // - Mode 2 (CPOL=1, CPHA=0): Clock idle high, sample on falling edge, setup on rising edge
                    // - Mode 3 (CPOL=1, CPHA=1): Clock idle high, sample on rising edge, setup on falling edge
                    // 根据SPI模式处理时钟和数据传输
                    // 支持标准的四种SPI模式
                    // -----------------------------------------------------------------
                    case (spi_mode)
                        // -------------------------------------------------------------
                        // 模式0: CPOL=0, CPHA=0
                        // 时钟空闲时为低电平，数据在第一个时钟边沿采样
                        // -------------------------------------------------------------
                        2'b00: begin
                            if (~sclk) begin
                                // 时钟上升沿：输出数据
                                sclk <= 1'b1;
                                mosi <= (bit_count < 5'd32) ? command_reg[31-bit_count] : 1'b0;
                            end else begin
                                // 时钟下降沿：采样数据
                                sclk <= 1'b0;
                                if (bit_count < 5'd32) begin
                                    shift_reg[31-bit_count] <= miso;  // 采样MISO数据
                                    bit_count <= bit_count + 1;      // 位计数器递增
                                end
                            end
                        end
                        
                        // -------------------------------------------------------------
                        // 模式1: CPOL=0, CPHA=1
                        // 时钟空闲时为低电平，数据在第二个时钟边沿采样
                        // -------------------------------------------------------------
                        2'b01: begin
                            if (~sclk) begin
                                // 第一个时钟边沿：准备数据
                                sclk <= 1'b1;
                            end else begin
                                // 第二个时钟边沿：输出数据并采样
                                sclk <= 1'b0;
                                mosi <= (bit_count < 5'd32) ? command_reg[31-bit_count] : 1'b0;
                                if (bit_count < 5'd32) begin
                                    shift_reg[31-bit_count] <= miso;  // 采样MISO数据
                                    bit_count <= bit_count + 1;      // 位计数器递增
                                end
                            end
                        end
                        
                        // -------------------------------------------------------------
                        // 模式2: CPOL=1, CPHA=0
                        // 时钟空闲时为高电平，数据在第一个时钟边沿采样
                        // -------------------------------------------------------------
                        2'b10: begin
                            if (sclk) begin
                                // 时钟下降沿：输出数据
                                sclk <= 1'b0;
                                mosi <= (bit_count < 5'd32) ? command_reg[31-bit_count] : 1'b0;
                            end else begin
                                // 时钟上升沿：采样数据
                                sclk <= 1'b1;
                                if (bit_count < 5'd32) begin
                                    shift_reg[31-bit_count] <= miso;  // 采样MISO数据
                                    bit_count <= bit_count + 1;      // 位计数器递增
                                end
                            end
                        end
                        
                        // -------------------------------------------------------------
                        // 模式3: CPOL=1, CPHA=1
                        // 时钟空闲时为高电平，数据在第二个时钟边沿采样
                        // -------------------------------------------------------------
                        2'b11: begin
                            if (sclk) begin
                                // 第一个时钟边沿：准备数据
                                sclk <= 1'b0;
                            end else begin
                                // 第二个时钟边沿：输出数据并采样
                                sclk <= 1'b1;
                                mosi <= (bit_count < 5'd32) ? command_reg[31-bit_count] : 1'b0;
                                if (bit_count < 5'd32) begin
                                    shift_reg[31-bit_count] <= miso;  // 采样MISO数据
                                    bit_count <= bit_count + 1;      // 位计数器递增
                                end
                            end
                        end
                    endcase
                end
            end
            
            // ---------------------------------------------------------------------
            // CS_DEASSERT状态 - 片选拉高状态处理
            // 拉高CS_N信号结束SPI传输，并处理接收到的响应数据
            // ---------------------------------------------------------------------
            CS_DEASSERT: begin
                cs_n <= 1'b1;                           // 拉高CS_N信号结束传输
                sclk <= (spi_mode == 2'b10) || (spi_mode == 2'b11);  // 根据SPI模式恢复SCLK状态
                mosi <= 1'b0;                           // MOSI恢复为低电平
                response_data <= shift_reg;             // 保存接收到的响应数据
                response_valid <= 1'b1;                 // 设置响应数据有效标志
                busy <= 1'b0;                           // 清除忙标志
                
                // -----------------------------------------------------------------
                // Win/lose counter implementation details:
                // - Response data MSB (bit 31) determines game outcome
                // - 1 = Win (increment win_counter)
                // - 0 = Loss (increment lose_counter)
                // - Simplified logic for basic game feedback
                // 更新胜负计数器（简化实现）
                // 根据响应数据的最高位判断输赢并更新计数器
                // -----------------------------------------------------------------
                if (response_data[31]) begin
                    win_counter <= win_counter + 1;     // 最高位为1表示获胜
                end else begin
                    lose_counter <= lose_counter + 1;   // 最高位为0表示失败
                end
            end
            
            // ---------------------------------------------------------------------
            // DONE状态 - 完成状态处理
            // 清理状态并准备下一次传输
            // ---------------------------------------------------------------------
            DONE: begin
                cs_n <= auto_cs_n ? manual_cs_n : 1'b1;  // 根据控制模式设置CS_N
                sclk <= (spi_mode == 2'b10) || (spi_mode == 2'b11);  // 恢复SCLK状态
                mosi <= 1'b0;                           // MOSI保持低电平
                response_valid <= 1'b0;                 // 清除响应有效标志
                busy <= 1'b0;                           // 清除忙标志
            end
        endcase
    end
end

endmodule