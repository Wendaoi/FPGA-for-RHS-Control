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
    // A1和A2通道电极使能控制
    // 用于控制每个通道中16个电极的使能状态
    // -------------------------------------------------------------------------
    input wire [15:0] a1_electrode_enable,  // A1通道16个电极的使能控制
    input wire [15:0] a2_electrode_enable,  // A2通道16个电极的使能控制
    
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
    
    // A1和A2通道尖峰数总和输出
    output reg [DATA_WIDTH-1:0] a1_spike_sum,                   // A1通道16个电极的尖峰总数
    output reg [DATA_WIDTH-1:0] a2_spike_sum,                   // A2通道16个电极的尖峰总数
    
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
                // 每个电极单独处理，不需要跳过任何电极
                begin
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
                // 不需要特殊处理，所有电极都进行滤波和尖峰检测
                
                // 保存当前数据用于下次计算
                prev_data[i] <= raw_data[i];
            end
            
            data_out_valid <= 1'b1;
            processing_done <= 1'b1;
            
            // 更新尖峰计数
            for (i = 0; i < CHANNELS; i = i + 1) begin
                spike_count[i] <= spike_counter[i];
            end
            
            // 计算A1和A2通道的尖峰数总和
            // 假设通道0和1分别对应A1和A2通道
            a1_spike_sum <= spike_counter[0];  // A1通道尖峰数总和
            a2_spike_sum <= spike_counter[1];  // A2通道尖峰数总和
        end else begin
            data_out_valid <= 1'b0;
            processing_done <= 1'b0;
        end
    end
end

endmodule