`timescale 1ns/1ps

//--------------------------------------------------------------------------
// 数据输出模块 - 增强版旁路控制器
// 
// 功能描述：
// 本模块作为神经刺激与游戏系统的数据输出接口，负责将游戏结果、神经信号数据
// 和电极分组配置信息转换为SPI命令格式输出到外部设备。
// 
// 主要特性：
// - 支持4种游戏模式：闭环反馈、静默反馈、无反馈、对照组
// - 支持电极分组动态配置（最多10组，每组8个电极）
// - 实时神经信号数据处理和输出
// - 游戏结果统计与输出
//--------------------------------------------------------------------------
module data_output_module #(
    parameter DATA_WIDTH = 16,                  // 神经信号数据位宽
    parameter CMD_WIDTH = 32,                   // SPI命令位宽
    parameter CHANNELS = 8,                     // 神经信号通道数
    parameter GROUPS = 10,                      // 电极分组数量
    parameter ELECTRODES_PER_GROUP = 8          // 每组电极数量
) (
    // 系统时钟与复位
    input wire clk,                              // 主时钟输入
    input wire reset,                            // 异步复位信号，高电平有效
    
    // 游戏模块接口
    input wire [7:0] ball_x,                     // 乒乓球X坐标（0-255）
    input wire [7:0] ball_y,                     // 乒乓球Y坐标（0-255）
    input wire [7:0] win_counter,                // 获胜次数计数器
    input wire [7:0] lose_counter,               // 失败次数计数器
    input wire game_result,                      // 单局游戏结果：1=赢，0=输
    input wire result_en,                        // 游戏结果使能信号，高电平表示结果有效
    
    // 神经信号处理接口
    input wire [DATA_WIDTH-1:0] spike_count [0:CHANNELS-1],  // 各通道尖峰计数
    input wire spike_data_valid,                              // 尖峰数据有效标志
    
    // 电极分组控制接口
    input wire [3:0] current_group,            // 当前操作的电极组号（0-9）
    input wire [1:0] group_function,           // 组功能配置：00=采集，01=刺激，10=交替，11=禁用
    
    // 控制接口
    input wire [1:0] game_mode,                // 游戏模式选择：
                                                // 00: 闭环反馈 - 实时神经反馈
                                                // 01: 静默反馈 - 记录神经活动但不反馈
                                                // 10: 无反馈 - 仅游戏控制
                                                // 11: 对照组 - 纯记录模式
    input wire output_enable,                   // 输出使能信号，高电平有效
    
    // SPI命令输出接口
    output reg [CMD_WIDTH-1:0] spi_command,     // 32位SPI命令输出
    output reg command_valid,                   // 命令有效标志
    input wire command_ready,                   // 外部设备准备好接收命令
    
    // 状态输出
    output reg output_done                      // 单次输出完成标志，高电平脉冲
);

// 内部信号定义
reg [2:0] state;                            // 状态机当前状态
reg [CMD_WIDTH-1:0] command_buffer;         // 命令缓冲区，存储待发送的SPI命令
reg command_buffer_valid;                   // 命令缓冲区有效标志

// 状态机定义 - 采用5状态设计确保可靠的数据传输
localparam IDLE        = 3'd0;              // 空闲状态，等待输出使能
localparam PREPARE_CMD = 3'd1;              // 准备命令，根据模式选择数据和命令类型
localparam SEND_CMD    = 3'd2;              // 发送命令，将命令放入输出接口
localparam WAIT_ACK    = 3'd3;              // 等待确认，等待外部设备接收命令
localparam DONE        = 3'd4;              // 完成状态，输出完成脉冲信号

// SPI命令类型定义 - 高8位作为命令标识符，低24位作为数据负载
localparam CMD_GAME_DATA       = 32'h10000000;  // 游戏结果数据命令（最高位为0001）
localparam CMD_SPIKE_DATA      = 32'h20000000;  // 神经尖峰数据命令（最高位为0010）
localparam CMD_CONTROL         = 32'h30000000;  // 控制命令（最高位为0011）
localparam CMD_ELECTRODE_CONFIG= 32'h40000000;  // 电极分组配置命令（最高位为0100）

integer i;                                    // 循环计数器，用于遍历神经通道

always @(posedge clk or posedge reset) begin
    if (reset) begin
        state <= IDLE;
        spi_command <= 32'h00000000;
        command_valid <= 1'b0;
        command_buffer_valid <= 1'b0;
        output_done <= 1'b0;
    end else begin
        case (state)
            IDLE: begin
                command_valid <= 1'b0;
                output_done <= 1'b0;
                
                if (output_enable) begin
                    state <= PREPARE_CMD;
                end
            end
            
            //------------------------------------------------------------------
            // 命令准备状态：根据不同的游戏模式选择和数据可用性，构建相应的SPI命令
            //------------------------------------------------------------------
            PREPARE_CMD: begin
                // 优先级排序：游戏结果 > 尖峰数据 > 电极配置 > 控制数据
                case (game_mode)
                    //=======================================================================================
                    // 模式 00: 闭环反馈模式
                    // 描述：最完整的模式下，所有数据都被采集并用于游戏反馈控制
                    // 优先级：游戏结果(W/L) → 尖峰信号 → 电极分组配置 → 游戏控制数据(球位置)
                    //=======================================================================================
                    2'b00: begin  // 闭环反馈 - 完整数据交换模式
                        if (result_en) begin
                            // 发送游戏结果数据到外部设备
                            // 命令格式：[0001][游戏结果][7位保留][赢计数][输计数]
                            command_buffer <= CMD_GAME_DATA | 
                                            {game_result, 7'h00, win_counter, lose_counter};
                        end else if (spike_data_valid) begin
                            // 发送尖峰数据（简化实现：当多通道同时有效时，优先发送通道0数据）
                            // 实际应用中可考虑通道选择策略：轮询、优先级、或数据融合
                            command_buffer <= CMD_SPIKE_DATA | spike_count[0];
                        end else if (current_group < GROUPS) begin
                            // 发送电极分组配置命令
                            // 格式：[0100][0001][组号][功能配置][16位配置数据]
                            command_buffer <= CMD_ELECTRODE_CONFIG | 
                                            {4'b0001, current_group, group_function, 16'h0000};
                        end else begin
                            // 发送游戏控制命令（主要包含球的位置信息）
                            // 格式：[0011][球X坐标][球Y坐标][8位保留]
                            command_buffer <= CMD_CONTROL | {ball_x, ball_y};
                        end
                    end
                    
                    //=======================================================================================
                    // 模式 01: 静默反馈模式  
                    // 描述：记录神经活动但不提供实时反馈，主要用于基线数据收集
                    // 特点：屏蔽真实的游戏结果，发送中性的结果数据；不发送尖峰数据
                    //=======================================================================================
                    2'b01: begin  // 静默反馈 - 基线数据采集模式
                        if (result_en) begin
                            // 发送"中性化"的游戏结果（屏蔽胜负差异，减少主观干扰）
                            // 将真实游戏结果放入次高位，实验者可选择是否分析此数据
                            command_buffer <= CMD_GAME_DATA | 
                                            {1'b0, game_result, 6'h00, win_counter, lose_counter};
                        end else if (current_group < GROUPS) begin
                            // 发送电极分组配置命令
                            command_buffer <= CMD_ELECTRODE_CONFIG | 
                                            {4'b0001, current_group, group_function, 16'h0000};
                        end else begin
                            // 空命令模式，维持系统时钟同步但不传输有效数据
                            // 确保在外部设备端保持统一的命令接收节拍
                            command_buffer <= CMD_CONTROL | 32'h00000000;
                        end
                    end
                    
                    //=======================================================================================
                    // 模式 10: 无反馈模式
                    // 描述：纯游戏模式，不采集神经信号，仅用于行为学研究
                    // 特点：只发送电极分组配置以维持硬件同步，其他数据均被屏蔽
                    //=======================================================================================
                    2'b10: begin  // 无反馈 - 纯行为学实验模式
                        if (current_group < GROUPS) begin
                            // 仅发送电极分组配置命令，用于维持硬件系统同步
                            // 此时电极可配置为固定模式（如全采集或全刺激）
                            command_buffer <= CMD_ELECTRODE_CONFIG | 
                                            {4'b0001, current_group, group_function, 16'h0000};
                        end else begin
                            // 发送空命令以保持命令传输的节奏一致性
                            command_buffer <= CMD_CONTROL | 32'h00000000;
                        end
                    end
                    
                    //=======================================================================================
                    // 模式 11: 对照组模式
                    // 描述：仅记录神经信号，不进行游戏控制或反馈
                    // 应用：用于研究自发的神经活动模式，或与其他模式的基线对比
                    //=======================================================================================
                    2'b11: begin  // 对照组 - 纯神经记录模式
                        if (spike_data_valid) begin
                            // 发送尖峰数据进行离线分析
                            // 此模式下尖峰数据具有最高优先级，确保完整记录神经活动
                            command_buffer <= CMD_SPIKE_DATA | spike_count[0];
                        end else if (current_group < GROUPS) begin
                            // 发送电极分组配置命令
                            // 神经科学研究中，常需要对比不同电极配置下的活动模式
                            command_buffer <= CMD_ELECTRODE_CONFIG | 
                                            {4'b0001, current_group, group_function, 16'h0000};
                        end else begin
                            // 发送空命令，保持系统同步
                            command_buffer <= CMD_CONTROL | 32'h00000000;
                        end
                    end
                endcase
                
                // 标记命令缓冲区有效，准备进入发送阶段
                command_buffer_valid <= 1'b1;
                state <= SEND_CMD;
            end
            
            //------------------------------------------------------------------
            // 命令发送状态：将准备好的命令传输到输出接口
            //------------------------------------------------------------------
            SEND_CMD: begin
                if (command_buffer_valid) begin
                    // 将命令缓冲区的数据复制到SPI输出接口
                    spi_command <= command_buffer;
                    // 拉高命令有效信号，通知外部设备数据已准备好
                    command_valid <= 1'b1;
                    // 转入等待确认状态，等待外部设备接收命令
                    state <= WAIT_ACK;
                end
                // 注意：如果命令缓冲区无效，将保持在此状态直到命令准备完成
                // 这种情况在正常操作中不应出现，是一种保护机制
            end
            
            //------------------------------------------------------------------
            // 等待确认状态：等待外部设备接收并确认命令
            //------------------------------------------------------------------
            WAIT_ACK: begin
                if (command_ready) begin
                    // 外部设备已准备好接收命令，可以完成本次传输
                    command_valid <= 1'b0;          // 拉低有效信号，结束本次命令传输
                    command_buffer_valid <= 1'b0;   // 清空命令缓冲区有效标志
                    output_done <= 1'b1;            // 产生完成脉冲，通知上游模块本次输出已完成
                    state <= DONE;                  // 进入完成状态
                end
                // 如果外部设备暂时没有准备好，将保持等待状态
                // 这种设计确保命令传输的可靠性，避免数据丢失
            end
            
            //------------------------------------------------------------------
            // 完成状态：产生完成脉冲并返回空闲状态
            //------------------------------------------------------------------
            DONE: begin
                // 拉低完成信号，产生一个时钟周期的高电平脉冲
                // 这种脉冲式设计便于上游模块检测完成事件
                output_done <= 1'b0;
                // 返回空闲状态，开始等待下一次输出请求
                state <= IDLE;
            end
        endcase
    end
end

endmodule