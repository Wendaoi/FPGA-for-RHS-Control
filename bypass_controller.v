`timescale 1ns/1ps

module bypass_controller (
    // 系统时钟和复位
    input wire clk,
    input wire reset,
    
    // 控制接口 - 从WireIn端点接收
    input wire bypass_enable,           // 旁路功能启用
    input wire [31:0] command_data,     // 待发送的32位命令数据
    input wire command_valid,           // 命令数据有效信号
    input wire [1:0] spi_mode,          // SPI模式选择 (00:模式0, 01:模式1, 10:模式2, 11:模式3)
    input wire auto_cs_n,               // 自动CS_N控制 (0:自动控制, 1:手动控制)
    input wire manual_cs_n,             // 手动CS_N控制 (当auto_cs_n=1时有效)
    
    // 状态反馈 - 通过WireOut端点输出
    output reg [31:0] response_data,    // 接收到的32位响应数据
    output reg response_valid,          // 响应数据有效信号
    output reg busy,                    // 模块忙信号
    
    // SPI接口 - 连接到主SPI总线
    output reg cs_n,                    // 片选信号 (低有效)
    output reg sclk,                    // 时钟信号
    output reg mosi,                    // 主出从入数据线
    input wire miso                     // 主入从出数据线
);

// 状态机定义
localparam IDLE        = 4'd0;
localparam CS_ASSERT   = 4'd1;
localparam TRANSFER    = 4'd2;
localparam CS_DEASSERT = 4'd3;
localparam DONE        = 4'd4;

// 内部信号声明
reg [3:0] state, next_state;
reg [31:0] shift_reg;           // 移位寄存器
reg [4:0] bit_count;            // 位计数器
reg [3:0] delay_counter;        // 延迟计数器
reg [31:0] command_reg;         // 命令寄存器
reg command_reg_valid;          // 命令寄存器有效标志

// SPI时钟相关信号
reg sclk_prev;
wire spi_clk_rising_edge = (sclk & ~sclk_prev);
wire spi_clk_falling_edge = (~sclk & sclk_prev);

// 时钟边沿检测
always @(posedge clk) begin
    sclk_prev <= sclk;
end

// 命令寄存器 - 存储待发送的命令
always @(posedge clk or posedge reset) begin
    if (reset) begin
        command_reg <= 32'h00000000;
        command_reg_valid <= 1'b0;
    end else begin
        if (command_valid && bypass_enable) begin
            command_reg <= command_data;
            command_reg_valid <= 1'b1;
        end else if (state == DONE) begin
            command_reg_valid <= 1'b0;
        end
    end
end

// 主状态机
always @(posedge clk or posedge reset) begin
    if (reset) begin
        state <= IDLE;
    end else begin
        state <= next_state;
    end
end

// 状态转移逻辑
always @(*) begin
    case (state)
        IDLE: begin
            if (command_reg_valid && bypass_enable)
                next_state = CS_ASSERT;
            else
                next_state = IDLE;
        end
        
        CS_ASSERT: begin
            next_state = TRANSFER;
        end
        
        TRANSFER: begin
            if (bit_count == 5'd32)
                next_state = CS_DEASSERT;
            else
                next_state = TRANSFER;
        end
        
        CS_DEASSERT: begin
            next_state = DONE;
        end
        
        DONE: begin
            next_state = IDLE;
        end
        
        default: next_state = IDLE;
    endcase
end

// 状态机输出和数据处理
always @(posedge clk or posedge reset) begin
    if (reset) begin
        cs_n <= 1'b1;
        sclk <= 1'b0;
        mosi <= 1'b0;
        shift_reg <= 32'h00000000;
        bit_count <= 5'd0;
        delay_counter <= 4'd0;
        response_data <= 32'h00000000;
        response_valid <= 1'b0;
        busy <= 1'b0;
    end else begin
        case (state)
            IDLE: begin
                cs_n <= auto_cs_n ? manual_cs_n : 1'b1;
                sclk <= (spi_mode == 2'b10) || (spi_mode == 2'b11);  // 模式2和3时SCLK初始为高
                mosi <= 1'b0;
                shift_reg <= 32'h00000000;
                bit_count <= 5'd0;
                delay_counter <= 4'd0;
                response_valid <= 1'b0;
                busy <= 1'b0;
            end
            
            CS_ASSERT: begin
                cs_n <= 1'b0;  // 拉低CS_N
                sclk <= (spi_mode == 2'b10) || (spi_mode == 2'b11);  // 模式2和3时SCLK初始为高
                mosi <= command_reg[31];  // 输出最高位
                shift_reg <= 32'h00000000;
                bit_count <= 5'd0;
                delay_counter <= 4'd2;  // 短暂延迟
                response_valid <= 1'b0;
                busy <= 1'b1;
            end
            
            TRANSFER: begin
                if (delay_counter > 4'd0) begin
                    delay_counter <= delay_counter - 1;
                end else begin
                    // 根据SPI模式处理时钟和数据
                    case (spi_mode)
                        2'b00: begin  // 模式0: CPOL=0, CPHA=0
                            if (~sclk) begin
                                sclk <= 1'b1;
                                mosi <= (bit_count < 5'd32) ? command_reg[31-bit_count] : 1'b0;
                            end else begin
                                sclk <= 1'b0;
                                if (bit_count < 5'd32) begin
                                    shift_reg[31-bit_count] <= miso;
                                    bit_count <= bit_count + 1;
                                end
                            end
                        end
                        
                        2'b01: begin  // 模式1: CPOL=0, CPHA=1
                            if (~sclk) begin
                                sclk <= 1'b1;
                            end else begin
                                sclk <= 1'b0;
                                mosi <= (bit_count < 5'd32) ? command_reg[31-bit_count] : 1'b0;
                                if (bit_count < 5'd32) begin
                                    shift_reg[31-bit_count] <= miso;
                                    bit_count <= bit_count + 1;
                                end
                            end
                        end
                        
                        2'b10: begin  // 模式2: CPOL=1, CPHA=0
                            if (sclk) begin
                                sclk <= 1'b0;
                                mosi <= (bit_count < 5'd32) ? command_reg[31-bit_count] : 1'b0;
                            end else begin
                                sclk <= 1'b1;
                                if (bit_count < 5'd32) begin
                                    shift_reg[31-bit_count] <= miso;
                                    bit_count <= bit_count + 1;
                                end
                            end
                        end
                        
                        2'b11: begin  // 模式3: CPOL=1, CPHA=1
                            if (sclk) begin
                                sclk <= 1'b0;
                            end else begin
                                sclk <= 1'b1;
                                mosi <= (bit_count < 5'd32) ? command_reg[31-bit_count] : 1'b0;
                                if (bit_count < 5'd32) begin
                                    shift_reg[31-bit_count] <= miso;
                                    bit_count <= bit_count + 1;
                                end
                            end
                        end
                    endcase
                end
            end
            
            CS_DEASSERT: begin
                cs_n <= 1'b1;  // 拉高CS_N
                sclk <= (spi_mode == 2'b10) || (spi_mode == 2'b11);  // 模式2和3时SCLK回到高电平
                mosi <= 1'b0;
                response_data <= shift_reg;
                response_valid <= 1'b1;
                busy <= 1'b0;
            end
            
            DONE: begin
                cs_n <= auto_cs_n ? manual_cs_n : 1'b1;
                sclk <= (spi_mode == 2'b10) || (spi_mode == 2'b11);
                mosi <= 1'b0;
                response_valid <= 1'b0;
                busy <= 1'b0;
            end
        endcase
    end
end

endmodule