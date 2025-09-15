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
    
    // Programming interface for stim sequencer
    output reg [3:0] prog_channel_A1, prog_address_A1,
    output reg [4:0] prog_module_A1,
    output reg [15:0] prog_word_A1,
    output reg prog_trig_A1,
    
    output reg [3:0] prog_channel_A2, prog_address_A2,
    output reg [4:0] prog_module_A2,
    output reg [15:0] prog_word_A2,
    output reg prog_trig_A2,
    
    output reg [3:0] prog_channel_B1, prog_address_B1,
    output reg [4:0] prog_module_B1,
    output reg [15:0] prog_word_B1,
    output reg prog_trig_B1,
    
    output reg [3:0] prog_channel_B2, prog_address_B2,
    output reg [4:0] prog_module_B2,
    output reg [15:0] prog_word_B2,
    output reg prog_trig_B2,
    
    output reg [3:0] prog_channel_C1, prog_address_C1,
    output reg [4:0] prog_module_C1,
    output reg [15:0] prog_word_C1,
    output reg prog_trig_C1,
    
    output reg [3:0] prog_channel_C2, prog_address_C2,
    output reg [4:0] prog_module_C2,
    output reg [15:0] prog_word_C2,
    output reg prog_trig_C2,
    
    output reg [3:0] prog_channel_D1, prog_address_D1,
    output reg [4:0] prog_module_D1,
    output reg [15:0] prog_word_D1,
    output reg prog_trig_D1,
    
    output reg [3:0] prog_channel_D2, prog_address_D2,
    output reg [4:0] prog_module_D2,
    output reg [15:0] prog_word_D2,
    output reg prog_trig_D2
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
// 电极控制信号
// -------------------------------------------------------------------------

// A1和A2通道电极功能控制信号
reg [15:0] a1_electrode_enable;  // A1通道16个电极的使能控制
reg [15:0] a2_electrode_enable;  // A2通道16个电极的使能控制

// -------------------------------------------------------------------------
// SPI时钟相关信号
// -------------------------------------------------------------------------

reg sclk_prev;                      // 上一时钟周期的SCLK值，用于边沿检测
wire spi_clk_rising_edge = (sclk & ~sclk_prev);   // SCLK上升沿检测信号
wire spi_clk_falling_edge = (~sclk & sclk_prev);  // SCLK下降沿检测信号

// -------------------------------------------------------------------------
// 数据处理模块信号
// -------------------------------------------------------------------------

// A1和A2通道尖峰数总和
wire [DATA_WIDTH-1:0] a1_spike_sum;  // A1通道16个电极的尖峰总数
wire [DATA_WIDTH-1:0] a2_spike_sum;  // A2通道16个电极的尖峰总数

// 桨控制信号（基于A1和A2通道尖峰数比较）
reg [1:0] paddle_control_auto;  // 自动桨控制信号 [1]向上, [0]向下

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

// A1和A2通道尖峰数比较逻辑
// 根据A1和A2通道尖峰数的比较结果控制游戏桨的移动
always @(posedge clk or posedge reset) begin
    if (reset) begin
        paddle_control_auto <= 2'b00;  // 复位时桨控制信号清零
    end else if (filter_data_valid) begin
        // 当滤波数据有效时，比较A1和A2通道的尖峰总数
        if (a1_spike_sum > a2_spike_sum) begin
            // A1通道尖峰数大于A2通道，桨向上移动
            paddle_control_auto <= 2'b10;  // [1]拉高表示向上
        end else begin
            // A1通道尖峰数小于等于A2通道，桨向下移动
            paddle_control_auto <= 2'b01;  // [0]拉高表示向下
        end
    end
end

// 删除电极分组初始化代码
// 每个电极单独处理，无需分组

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
    .a1_electrode_enable(a1_electrode_enable),  // A1通道电极使能控制
    .a2_electrode_enable(a2_electrode_enable),  // A2通道电极使能控制
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
    .a1_electrode_enable(a1_electrode_enable),  // A1通道电极使能控制
    .a2_electrode_enable(a2_electrode_enable),  // A2通道电极使能控制
    .filter_mode(2'b00),                        // 滤波模式配置 (00:无滤波, 01:高通, 10:低通, 11:带通)
    .threshold(16'h1000),                       // 尖峰检测阈值配置
    .filter_enable(bypass_enable),              // 滤波使能信号连接
    .filtered_data(filtered_data),              // 滤波后数据输出连接
    .data_out_valid(filter_data_valid),         // 滤波数据输出有效信号连接
    .spike_count(spike_count),                  // 尖峰计数输出连接
    .a1_spike_sum(a1_spike_sum),                // A1通道尖峰总数输出连接
    .a2_spike_sum(a2_spike_sum),                // A2通道尖峰总数输出连接
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
    .a1_spike_sum(a1_spike_sum),                // A1通道尖峰总数输出
    .a2_spike_sum(a2_spike_sum),                // A2通道尖峰总数输出
    .game_mode(game_mode),                      // 游戏模式选择输入连接
    .output_enable(bypass_enable),              // 输出使能信号连接
    .spi_command(spi_command),                  // 生成的SPI命令输出连接
    .command_valid(command_output_valid),       // 命令输出有效信号连接
    .command_ready(command_output_ready),       // 命令输出就绪信号连接
    .output_done(output_done)                   // 输出完成信号连接
);

// -------------------------------------------------------------------------
// 游戏模块实例化
// -------------------------------------------------------------------------

Game #(
    .board_width(40),
    .board_height(16),
    .ball_velocity_x(1),
    .ball_velocity_y(1),
    .paddle_length(2),
    .paddle_velocity(1)
) game_inst (
    .reset(reset),
    .clk(clk),
    
    .game_start_valid(game_start_valid),
    .game_start_ready(game_start_ready),
    .game_end_valid(game_end_valid),
    .game_end_ready(game_end_ready),
    
    .paddle_control(paddle_control),
    .result_en(result_en),
    .game_result(game_result),
    
    .ball_x(ball_x),
    .ball_y(ball_y),
    
    .win_counter(win_counter),
    .lose_counter(lose_counter)
);

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
        // 等待编程触发信号被处理
        // ---------------------------------------------------------------------
        WAIT_STIM: begin
            // 在编程接口模式下，编程命令发送后直接转到完成状态
            next_state = DONE;               // 编程命令发送后直接转到完成状态
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
        response_data <= 32'h00000000;          // 响应数据寄存器清零
        response_valid <= 1'b0;                 // 响应数据有效标志清零
        busy <= 1'b0;                           // 忙信号清零
        win_counter <= 8'h00;                   // 获胜计数器清零
        lose_counter <= 8'h00;                  // 失败计数器清零
        command_processed <= 1'b0;              // 命令处理完成标志初始化为未完成
        cmd_delay_counter <= 4'd0;             // 命令延迟计数器初始化为0
        
        // Initialize programming interface signals
        prog_channel_A1 <= 4'd0; prog_address_A1 <= 4'd0;
        prog_module_A1 <= 5'd0;
        prog_word_A1 <= 16'd0;
        prog_trig_A1 <= 1'b0;
        
        prog_channel_A2 <= 4'd0; prog_address_A2 <= 4'd0;
        prog_module_A2 <= 5'd0;
        prog_word_A2 <= 16'd0;
        prog_trig_A2 <= 1'b0;
        
        prog_channel_B1 <= 4'd0; prog_address_B1 <= 4'd0;
        prog_module_B1 <= 5'd0;
        prog_word_B1 <= 16'd0;
        prog_trig_B1 <= 1'b0;
        
        prog_channel_B2 <= 4'd0; prog_address_B2 <= 4'd0;
        prog_module_B2 <= 5'd0;
        prog_word_B2 <= 16'd0;
        prog_trig_B2 <= 1'b0;
        
        prog_channel_C1 <= 4'd0; prog_address_C1 <= 4'd0;
        prog_module_C1 <= 5'd0;
        prog_word_C1 <= 16'd0;
        prog_trig_C1 <= 1'b0;
        
        prog_channel_C2 <= 4'd0; prog_address_C2 <= 4'd0;
        prog_module_C2 <= 5'd0;
        prog_word_C2 <= 16'd0;
        prog_trig_C2 <= 1'b0;
        
        prog_channel_D1 <= 4'd0; prog_address_D1 <= 4'd0;
        prog_module_D1 <= 5'd0;
        prog_word_D1 <= 16'd0;
        prog_trig_D1 <= 1'b0;
        
        prog_channel_D2 <= 4'd0; prog_address_D2 <= 4'd0;
        prog_module_D2 <= 5'd0;
        prog_word_D2 <= 16'd0;
        prog_trig_D2 <= 1'b0;
        
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
                response_valid <= 1'b0;                 // 清除响应有效标志
                busy <= 1'b0;                           // 清除忙标志
                command_processed <= 1'b0;              // 清除命令处理完成标志
                cmd_delay_counter <= 4'd0;             // 延迟计数器清零
                
                // Clear programming interface signals
                prog_trig_A1 <= 1'b0;
                prog_trig_A2 <= 1'b0;
                prog_trig_B1 <= 1'b0;
                prog_trig_B2 <= 1'b0;
                prog_trig_C1 <= 1'b0;
                prog_trig_C2 <= 1'b0;
                prog_trig_D1 <= 1'b0;
                prog_trig_D2 <= 1'b0;
            end
            
            // ---------------------------------------------------------------------
            // PROCESS状态 - 命令处理状态处理
            // 处理命令并生成相应的刺激控制信号
            // ---------------------------------------------------------------------
            PROCESS: begin
                response_valid <= 1'b0;                 // 清除响应有效标志
                busy <= 1'b1;                           // 设置忙标志表示正在进行处理
                command_processed <= 1'b0;              // 初始化命令处理完成标志
                
                // 根据命令类型生成相应的刺激控制信号
                case (command_reg[31:28])
                    // 电极分组配置命令 (0001)
                    4'b0001: begin
                        // Generate programming signals for stim sequencer
                        // For now, we'll just trigger a simple program command
                        prog_channel_A1 <= 4'd0;
                        prog_address_A1 <= 4'd0;
                        prog_module_A1 <= 5'd0;
                        prog_word_A1 <= 16'h0000;
                        prog_trig_A1 <= 1'b1;
                        
                        prog_channel_A2 <= 4'd0;
                        prog_address_A2 <= 4'd0;
                        prog_module_A2 <= 5'd1;
                        prog_word_A2 <= 16'h0000;
                        prog_trig_A2 <= 1'b1;
                        
                        prog_channel_B1 <= 4'd0;
                        prog_address_B1 <= 4'd0;
                        prog_module_B1 <= 5'd2;
                        prog_word_B1 <= 16'h0000;
                        prog_trig_B1 <= 1'b1;
                        
                        prog_channel_B2 <= 4'd0;
                        prog_address_B2 <= 4'd0;
                        prog_module_B2 <= 5'd3;
                        prog_word_B2 <= 16'h0000;
                        prog_trig_B2 <= 1'b1;
                        
                        prog_channel_C1 <= 4'd0;
                        prog_address_C1 <= 4'd0;
                        prog_module_C1 <= 5'd4;
                        prog_word_C1 <= 16'h0000;
                        prog_trig_C1 <= 1'b1;
                        
                        prog_channel_C2 <= 4'd0;
                        prog_address_C2 <= 4'd0;
                        prog_module_C2 <= 5'd5;
                        prog_word_C2 <= 16'h0000;
                        prog_trig_C2 <= 1'b1;
                        
                        prog_channel_D1 <= 4'd0;
                        prog_address_D1 <= 4'd0;
                        prog_module_D1 <= 5'd6;
                        prog_word_D1 <= 16'h0000;
                        prog_trig_D1 <= 1'b1;
                        
                        prog_channel_D2 <= 4'd0;
                        prog_address_D2 <= 4'd0;
                        prog_module_D2 <= 5'd7;
                        prog_word_D2 <= 16'h0000;
                        prog_trig_D2 <= 1'b1;
                    end
                    
                    // 游戏数据命令 (0002)
                    4'b0010: begin
                        // Generate programming signals for stim sequencer to send game data
                        prog_channel_A1 <= 4'd0;
                        prog_address_A1 <= 4'd4;  // Use address 4 for start stim
                        prog_module_A1 <= 5'd0;
                        prog_word_A1 <= 16'h0011; // Send game data on channel 17
                        prog_trig_A1 <= 1'b1;
                    end
                    
                    // 神经尖峰数据命令 (0011)
                    4'b0011: begin
                        // Generate programming signals for stim sequencer to send spike data
                        prog_channel_A1 <= 4'd0;
                        prog_address_A1 <= 4'd4;  // Use address 4 for start stim
                        prog_module_A1 <= 5'd0;
                        prog_word_A1 <= 16'h0012; // Send spike data on channel 18
                        prog_trig_A1 <= 1'b1;
                    end
                    
                    // 控制命令 (0100)
                    4'b0100: begin
                        // Generate programming signals for stim sequencer to send control data
                        prog_channel_A1 <= 4'd0;
                        prog_address_A1 <= 4'd4;  // Use address 4 for start stim
                        prog_module_A1 <= 5'd0;
                        prog_word_A1 <= 16'h0013; // Send control data on channel 19
                        prog_trig_A1 <= 1'b1;
                    end
                    
                    // 默认情况 - 安全关闭
                    default: begin
                        // Generate programming signals for stim sequencer to shutdown
                        prog_channel_A1 <= 4'd0;
                        prog_address_A1 <= 4'd4;  // Use address 4 for start stim
                        prog_module_A1 <= 5'd0;
                        prog_word_A1 <= 16'h0000; // Shutdown on channel 0
                        prog_trig_A1 <= 1'b1;
                    end
                endcase
                
                command_processed <= 1'b1;              // 标记命令处理完成
            end
            
            // ---------------------------------------------------------------------
            // SEND_STIM状态 - 发送刺激状态处理
            // 发送刺激控制信号到刺激序列器
            // ---------------------------------------------------------------------
            SEND_STIM: begin
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