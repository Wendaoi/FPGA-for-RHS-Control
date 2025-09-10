# 电极分组设计方案

## 设计目标
1. 支持将电极分为10组
2. 每组电极在每个SPI操作周期中可以分别定义其作用（收集电位信号或发送刺激）
3. 电极的作用可以根据当前游戏参数动态变化

## 数据结构设计

### 电极分组定义
```verilog
// 电极分组配置参数
parameter GROUPS = 10;           // 电极分组数量
parameter ELECTRODES_PER_GROUP = 8;  // 每组电极数量（可根据实际需要调整）
parameter TOTAL_ELECTRODES = GROUPS * ELECTRODES_PER_GROUP;  // 总电极数

// 电极分组映射表（示例，可在代码中修改）
// group_map[组号][电极号] = 实际电极编号
reg [7:0] group_map [0:GROUPS-1][0:ELECTRODES_PER_GROUP-1];

// 电极功能配置（每组电极的功能）
// 0: 收集电位信号, 1: 发送刺激
reg [1:0] electrode_function [0:GROUPS-1];  // 每组的功能配置
```

### SPI指令格式扩展
```verilog
// 扩展SPI指令以支持电极分组控制
// 原有指令格式: 32位
// 新指令格式:
// [31:28] 指令类型 (0000: 游戏数据, 0001: 电极分组配置, 0010: 尖峰数据, 0011: 控制命令)
// [27:24] 组号 (0-9)
// [23:16] 功能选择 (0: 收集信号, 1: 发送刺激)
// [15:0]  数据/参数
```

## 模块修改计划

### 1. enhanced_bypass_controller.v
- 添加电极分组配置参数
- 添加电极分组控制接口
- 修改SPI指令处理逻辑以支持电极分组

### 2. data_output_module.v
- 修改SPI命令生成逻辑以支持电极分组指令
- 添加电极分组配置命令生成

### 3. filter_processing_module.v
- 修改信号处理逻辑以支持按组处理电极信号
- 添加按组的尖峰检测功能

### 4. data_input_module.v
- 修改数据输入处理以支持电极分组

## 电极分组配置示例
```verilog
// 默认电极分组映射 (示例配置)
initial begin
    // Group 0: 电极 0-7
    group_map[0][0] = 0; group_map[0][1] = 1; group_map[0][2] = 2; group_map[0][3] = 3;
    group_map[0][4] = 4; group_map[0][5] = 5; group_map[0][6] = 6; group_map[0][7] = 7;
    
    // Group 1: 电极 8-15
    group_map[1][0] = 8; group_map[1][1] = 9; group_map[1][2] = 10; group_map[1][3] = 11;
    group_map[1][4] = 12; group_map[1][5] = 13; group_map[1][6] = 14; group_map[1][7] = 15;
    
    // ... 其他组的配置
    
    // 默认功能配置
    electrode_function[0] = 2'b00;  // Group 0: 收集信号
    electrode_function[1] = 2'b01;  // Group 1: 发送刺激
    // ... 其他组的配置
end
```