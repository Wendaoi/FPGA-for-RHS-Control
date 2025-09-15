`timescale 1ns / 1ps

module Game #(
	parameter board_width  	= 40,
    parameter board_height 	= 16,
    parameter ball_velocity_x = 1,
    parameter ball_velocity_y = 1,
    parameter paddle_length = 2,
    parameter paddle_velocity = 1
	)
	(
	input wire			reset,
	input wire			clk,

	input wire          game_start_valid,   //控制模块游戏开始握手信号
    output wire         game_start_ready,   //game模块游戏开始握手信号
    input wire          game_end_valid,     //控制模块游戏结束握手信号
    output wire         game_end_ready,     //game模块游戏结束握手信号

    input wire  [1:0]   paddle_control,     //control[1]拉高向上，control[0]拉高向下，均为0不动
    output wire         result_en,          //每轮游戏结果使能信号
    output wire         game_result,        //1表示赢，0表示输

    output reg  [7:0]   ball_x,
    output reg  [7:0]   ball_y,

    output reg  [7:0]   win_counter,        //多轮游戏中赢的轮数
    output reg  [7:0]   lose_counter        //多轮游戏中输的轮数
 	);

    reg [7:0] paddle_pos;        //板子上端的位置
    reg       ball_x_direction;  //1表示向左，0表示向右
    reg       ball_y_direction;  //1表示向上，0表示向下

    reg       game_result_reg;

    //游戏状态机，游戏未开始时处于game_wait状态，开始后处于game_running，每轮结束进入game_end
    reg [1:0] current_game_state;
    reg [1:0] next_game_state;

    parameter GAME_WAIT = 2'b0,
              GAME_RUNNING = 2'b1,
              GAME_END = 2'b2;
    
    always @(posedge clk) begin
        if(reset)begin
            current_game_state <= 2'b0;
        end
        else begin
            current_game_state <= next_game_state;
        end
    end

    always @(*) begin   
        case (current_game_state)
            GAME_WAIT: 
                if(game_start_valid && game_start_ready) next_game_state <= GAME_RUNNING;
                else next_game_state <= GAME_WAIT;
            
            GAME_RUNNING:
                //球的方向向左，x方向距离小于x方向速度，也可以写成ball_x=0
                if(ball_x_direction && (ball_x < ball_velocity_x)) next_game_state <= GAME_END;
                else next_game_state <= GAME_RUNNING;
            
            GAME_END:

                if(game_end_valid && game_end_ready) next_game_state <= GAME_WAIT;
                else if(game_start_valid & game_start_ready) next_game_state <= GAME_RUNNING;
                else next_game_state <= GAME_END;

            default: next_game_state <= GAME_WAIT;
        endcase
    end

    //此模块处理球的位置和方向
    always @(posedge clk) begin

        if(reset)begin
            ball_x <= (board_width >> 1'b1);
            ball_y <= (board_height >> 1'b1);
            ball_x_direction <= 1'b0;
            ball_y_direction <= 1'b0;
        end
        //等待开始和上一轮游戏输了都需要复位
        //**这里的条件写法有问题，应该是or
        else if(current_game_state == GAME_WAIT && (current_game_state == GAME_END && game_result == 1'b0))begin
            ball_x <= (board_width >> 1'b1);
            ball_y <= (board_height >> 1'b1);
            //这里的方向如果是随机的需要变化写法
            ball_x_direction <= 1'b0;
            ball_y_direction <= 1'b0;
        end
        
        //游戏进行中球的位置与方向变化
        //**不是所有情况都反弹，与实验设置有关，需要和球板一起判断
        else if(current_game_state == GAME_RUNNING)begin
            //球向右向下
            if(ball_x_direction == 1'b0 && ball_y_direction == 1'b0)begin
                //处理球快要碰壁和已经碰壁的边界情况
                if( (ball_x + ball_velocity_x)>board_width )begin
                    ball_x <= board_width - ball_velocity_x + board_width - ball_x;
                    ball_x_direction <= 1'b1;
                end
                else if(ball_y<ball_velocity_y)begin
                    ball_y <= ball_velocity_y - ball_y;
                    ball_y_direction <= 1'b1;
                end
                else begin
                    ball_x <= ball_x + ball_velocity_x;
                    ball_y <= ball_y - ball_velocity_y;
                end
            end
            //球向左向下
            else if(ball_x_direction == 1'b1 && ball_y_direction == 1'b0)begin
                if(ball_x < ball_velocity_x)begin
                    ball_x <= ball_velocity_x - ball_x;
                    ball_x_direction <= 1'b0;
                end
                else if(ball_y<ball_velocity_y)begin
                    ball_y <= ball_velocity_y - ball_y;
                    ball_y_direction <= 1'b1;
                end
                else begin
                    ball_x <= ball_x - ball_velocity_x;
                    ball_y <= ball_y - ball_velocity_y;
                end
            end
            //球向右向上
            else if(ball_x_direction == 1'b0 && ball_y_direction == 1'b1)begin
                if( (ball_x + ball_velocity_x)>board_width )begin
                    ball_x <= board_width - ball_velocity_x + board_width - ball_x;
                    ball_x_direction <= 1'b1;
                end
                else if( (ball_y + ball_velocity_y)>board_height )begin
                    ball_y <= board_height - ball_velocity_y + board_height - ball_y;
                    ball_y_direction <= 1'b0;
                end
                else begin
                    ball_x <= ball_x + ball_velocity_x;
                    ball_y <= ball_y + ball_velocity_y;
                end
            end
            //球向左向上
            else if(ball_x_direction == 1'b1 && ball_y_direction == 1'b1)begin
                if(ball_x < ball_velocity_x)begin
                    ball_x <= ball_velocity_x - ball_x;
                    ball_x_direction <= 1'b0;
                end
                else if( (ball_y + ball_velocity_y)>board_height )begin
                    ball_y <= board_height - ball_velocity_y + board_height - ball_y;
                    ball_y_direction <= 1'b0;
                end
                else begin
                    ball_x <= ball_x - ball_velocity_x;
                    ball_y <= ball_y + ball_velocity_y;
                end
            end
        end
    end

    //此模块处理板子的位置
    always @(posedge clk) begin
        if(reset)begin
            paddle_pos <= ((board_height >> 1'b1) + (paddle_length >> 1'b1));
        end
        else if(current_game_state == GAME_WAIT && (current_game_state == GAME_END && game_result == 1'b0))begin
            paddle_pos <= ((board_height >> 1'b1) + (paddle_length >> 1'b1));
        end
        else if(current_game_state == GAME_RUNNING)begin
            if(paddle_control[1])begin
                if(paddle_pos + paddle_velocity >= board_height)begin
                    paddle_pos <= board_height;
                end
                else begin
                    paddle_pos <= paddle_pos + paddle_velocity;
                end
            end
            else if(paddle_control[0])begin
                if(paddle_pos - paddle_length <= paddle_velocity)begin
                    paddle_pos <= paddle_length;
                end
                else begin
                    paddle_pos <= paddle_pos - paddle_velocity;
                end
            end
        end
    end

    //此模块用于游戏输赢结果相关的变量赋值
    always @(posedge clk) begin
        if(reset)begin
            win_counter <= 8'b0;
            lose_counter <= 8'b0;
            game_result_reg <= 1'b0;
        end
        else if(current_game_state == GAME_WAIT)begin
            win_counter <= 8'b0;
            lose_counter <= 8'b0;
            game_result_reg <= 1'b0;
        end
        else if(current_game_state == GAME_RUNNING)begin
            //这里要求小球一定在周期结束时触壁，也即小球x方向的速度一定能整除board宽度，否则要用除法判断
            //**触壁条件可以改成小于等于0？
            if(ball_x == 8'b0)begin
                if(ball_y <= paddle_pos && ball_y >= paddle_pos - paddle_length)begin
                    win_counter <= win_counter + 8'b1;
                    game_result_reg <= 1'b1;
                end
                else begin
                    lose_counter <= lose_counter + 8'b1;
                    game_result_reg <= 1'b0;
                end
            end
        end
    end

    assign game_result = game_result_reg;
    assign result_en = current_game_state == GAME_END;

    assign game_start_ready = (current_game_state == GAME_WAIT) || (current_game_state == GAME_END);
    assign game_end_ready = current_game_state == GAME_END;

endmodule