// =============================================================================
// 模块名称: filter_processing_module
// 描述:    滤波处理模块，负责对原始生物电信号进行滤波和尖峰检测
//          根据电极分组配置决定是否对特定电极进行滤波处理
// =============================================================================

`timescale 1ns/1ps

module filter_processing_module #(
    parameter DATA_WIDTH = 16,           // 数据宽度 (默认16位)
    parameter CHANNELS = 8,             // 通道数量 (默认8通道)
    parameter GROUPS = 10,              // 电极分组数量 (默认10组)
    parameter ELECTRODES_PER_GROUP = 8, // 每组电极数量 (默认每组8个电极)
    parameter THRESHOLD = 16'h1000       // 默认尖峰检测阈值
) (
    // -------------------------------------------------------------------------
    // 系统时钟和复位信号
    // -------------------------------------------------------------------------
    input wire clk,                     // 系统时钟
    input wire reset,                   // 系统复位信号 (高电平有效)
    
    // -------------------------------------------------------------------------
    // 数据输入接口
    // 接收来自数据输入模块的原始生物电信号数据
    // -------------------------------------------------------------------------
    input wire [DATA_WIDTH-1:0] raw_data [0:CHANNELS-1],  // 原始数据输入 (每个通道DATA_WIDTH位)
    input wire data_valid,                                 // 数据有效信号
    
    // -------------------------------------------------------------------------
    // 电极分组控制接口
    // 用于配置电极分组和功能，决定哪些电极需要进行滤波处理
    // -------------------------------------------------------------------------
    // 电极分组映射表
    // group_map[组号][电极号] = 实际电极编号
    input wire [7:0] group_map [0:GROUPS-1][0:ELECTRODES_PER_GROUP-1],
    
    // 电极功能配置数组
    // 每组电极的功能配置：
    // 00: 收集电位信号
    // 01: 发送刺激
    // 10: 高阻态
    // 11: 保留
    input wire [1:0] electrode_function [0:GROUPS-1],
    
    // 当前操作的组号 (0-9)
    input wire [3:0] current_group,
    
    // -------------------------------------------------------------------------
    // 控制接口
    // 配置滤波模式、阈值和使能信号
    // -------------------------------------------------------------------------
    // 滤波模式选择：
    // 00: 无滤波 (直通模式)
    // 01: 高通滤波
    // 10: 低通滤波
    // 11: 带通滤波
    input wire [1:0] filter_mode,
    
    // 尖峰检测阈值 (DATA_WIDTH位)
    input wire [DATA_WIDTH-1:0] threshold,
    
    // 滤波使能信号 (1:使能滤波处理, 0:禁用滤波处理)
    input wire filter_enable,
    
    // -------------------------------------------------------------------------
    // 数据输出接口
    // 向下游模块输出经过滤波处理的数据和尖峰计数
    // -------------------------------------------------------------------------
    output reg [DATA_WIDTH-1:0] filtered_data [0:CHANNELS-1],  // 滤波后数据输出
    output reg data_out_valid,                                   // 数据输出有效信号
    output reg [DATA_WIDTH-1:0] spike_count [0:CHANNELS-1],     // 每个通道的尖峰计数
    
    // -------------------------------------------------------------------------
    // 状态输出
    // 向控制模块报告处理完成状态
    // -------------------------------------------------------------------------
    output reg processing_done           // 处理完成信号
);

// 内部信号
reg [DATA_WIDTH-1:0] prev_data [0:CHANNELS-1];
reg [DATA_WIDTH-1:0] hp_filtered_data [0:CHANNELS-1];
reg [DATA_WIDTH-1:0] lp_filtered_data [0:CHANNELS-1];
reg [DATA_WIDTH-1:0] spike_counter [0:CHANNELS-1];

// 滤波系数（简化实现）
localparam HP_COEFF = 16'h7FFF;  // 0.5
localparam LP_COEFF = 16'h3FFF;  // 0.25

integer i;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        // 初始化数组
        for (i = 0; i < CHANNELS; i = i + 1) begin
            prev_data[i] <= {DATA_WIDTH{1'b0}};
            hp_filtered_data[i] <= {DATA_WIDTH{1'b0}};
            lp_filtered_data[i] <= {DATA_WIDTH{1'b0}};
            filtered_data[i] <= {DATA_WIDTH{1'b0}};
            spike_counter[i] <= {DATA_WIDTH{1'b0}};
            spike_count[i] <= {DATA_WIDTH{1'b0}};
        end
        data_out_valid <= 1'b0;
        processing_done <= 1'b0;
    end else begin
        if (filter_enable && data_valid) begin
            // 执行滤波处理
            for (i = 0; i < CHANNELS; i = i + 1) begin
                // 检查当前通道是否属于当前操作的组
                // 如果属于当前组且功能为发送刺激，则跳过滤波处理
                reg is_current_group_electrode;
                integer g, e;
                is_current_group_electrode = 1'b0;
                
                // 检查当前电极是否属于当前组
                for (g = 0; g < GROUPS; g = g + 1) begin
                    for (e = 0; e < ELECTRODES_PER_GROUP; e = e + 1) begin
                        if (group_map[g][e] == i && g == current_group && electrode_function[g] == 2'b01) begin
                            is_current_group_electrode = 1'b1;
                        end
                    end
                end
                
                // 如果不是当前组的刺激电极，则进行滤波处理
                if (!is_current_group_electrode) begin
                    // 高通滤波: y[n] = x[n] - x[n-1]
                    hp_filtered_data[i] <= raw_data[i] - prev_data[i];
                    
                    // 低通滤波: y[n] = a*x[n] + (1-a)*y[n-1]
                    lp_filtered_data[i] <= (LP_COEFF * raw_data[i] + (16'hFFFF - LP_COEFF) * lp_filtered_data[i]) >>> 16;
                    
                    // 根据模式选择输出
                    case (filter_mode)
                        2'b00: filtered_data[i] <= raw_data[i];  // 无滤波
                        2'b01: filtered_data[i] <= hp_filtered_data[i];  // 高通
                        2'b10: filtered_data[i] <= lp_filtered_data[i];  // 低通
                        2'b11: filtered_data[i] <= hp_filtered_data[i] + lp_filtered_data[i];  // 带通
                    endcase
                    
                    // 尖峰检测
                    if (filtered_data[i] > threshold) begin
                        spike_counter[i] <= spike_counter[i] + 1;
                    end
                end else begin
                    // 对于当前组的刺激电极，设置为默认值
                    filtered_data[i] <= {DATA_WIDTH{1'b0}};
                    // 不增加尖峰计数
                end
                
                // 保存当前数据用于下次计算
                prev_data[i] <= raw_data[i];
            end
            
            data_out_valid <= 1'b1;
            processing_done <= 1'b1;
            
            // 更新尖峰计数
            for (i = 0; i < CHANNELS; i = i + 1) begin
                spike_count[i] <= spike_counter[i];
            end
        end else begin
            data_out_valid <= 1'b0;
            processing_done <= 1'b0;
        end
    end
end

endmodule