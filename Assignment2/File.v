`timescale 1ns / 1ps
///////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    16:48:32 02/24/2017 
// Design Name: 
// Module Name:    sf 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// 
//
//////////////////////////////////////////////////////////////////////////////////
module functions
   (
	 
    input[4:0]  temp1,
	 input[1:0] selected,
	 input a,input b, input c, input d,
	 input RESET,	 
	 input myClock,	 
	 output[7:0] a
	 );
	 
	
	reg[4:0] counter = 0;
	reg[4:0] inp[0:9];
	reg[13:0] ans = 14'b0000000000000;
	reg[15:0] t2;
	reg[4:0] n = 4'b00001;
	reg[1:0] q;
	
 
 DeBounce bd(myClock, 1'b1, a, myNewClock);

always @(posedge myNewClock)
	begin
		if( counter <= n)
			case (counter)
				5'b00000:
					n <= temp1;
				5'b00001:
					inp[0] <= temp1;
				5'b00010:
					inp[1] <= temp1;
				5'b00011:
					inp[2] <= temp1;
				5'b00100:
					inp[3] <= temp1;
				5'b00101:
					inp[4] <= temp1;
				5'b00110:
					inp[5] <= temp1;
				5'b00111:
					inp[6] <= temp1;
				5'b01000:
					inp[7] <= temp1;
				5'b01001:
					inp[8] <= temp1;
				5'b01010:
					inp[9] <= temp1;
			endcase
	end

always @(negedge myNewClock)
	begin
	counter = counter + 1;
   end

reg[13:0] total;
reg[5:0] avgerage;
reg[13:0] sumsquare;
reg[13:0] variance = 14'b00000000000000;
integer i;

always @(posedge b)
	begin
	
	////
	if(selected==0)
				begin
				total = 0;
				for (i=0; i<10; i=i+1)
					begin
					total = total + inp[i];
					end
				t2 = total;			
				end
	if(selected==1)
				begin
				avgerage = 0;
				for (i=0; i<10; i=i+1)
					begin
					avgerage = avgerage + inp[i];
					end
				avgerage = avgerage/n;
				t2 = avgerage;			
				end
			
				begin
				sumsq=0;
				for (i=0; i<10; i=i+1)
					begin
					sumsquare = sumsquare + inp[i]*inp[i];
					end
				t2 = sumsquare;
				
				end				
			2'b11:
				begin
				variance = 0;
				for(i=0; i<10; i=i+1)
				begin
				if(i<n)
					begin
						if(inp[i]>avgerage)
						variance = variance + (inp[i]-avgerage)*(inp[i]-avgerage);
						else
						variance = variance + (avgerage-inp[i])*(avgerage-inp[i]);
					end
				end
				
				variance = variance/n;
				
				for(i=0; i<33; i=i+1)
				begin
				if( (i*i < variance ||  i*i == variance) )
					t2 = i;
				end
				
				//t2 = variance;
				end
	endcase
	end
	reg[7:0] sumT;
	
always @(*)
	if(c==0)
	begin
	for ( i=0; i<8; i=i+1)
		sumT[i] = t2[i];
	end
	else
	begin
	for ( i=0; i<8; i=i+1)
		sumT[i] = t2[i+8];
	end
	
assign {sum} = sumT;

endmodule

module  DeBounce 
	(
	input 			clock, n_reset, button_in,				// inputs
	output reg 	DB_out													// output
	);


	parameter N = 11 ;		// (2^ (21-1) )/ 38 MHz = 32 ms debounce time
////---------------- internal variables ---------------
	reg  [N-1 : 0]	q_reg;							// timing regs
	reg  [N-1 : 0]	q_next;
	reg DFF1, DFF2;									// input flip-flops
	wire q_add;											// control flags
	wire q_reset;
//// ------------------------------------------------------

////contenious assignment for counter control
	assign q_reset = (DFF1  ^ DFF2);		// xor input flip flops to look for level chage to reset counter
	assign  q_add = ~(q_reg[N-1]);			// add to counter when q_reg msb is equal to 0
	
//// combo counter to manage q_next	
	always @ ( q_reset, q_add, q_reg)
		begin
			case( {q_reset , q_add})
				2'b00 :
						q_next <= q_reg;
				2'b01 :
						q_next <= q_reg + 1;
				default :
						q_next <= { N {1'b0} };
			endcase 	
		end
	
//// Flip flop inputs and q_reg update
	always @ ( posedge clock )
		begin
			if(n_reset ==  1'b0)
				begin
					DFF1 <= 1'b0;
					DFF2 <= 1'b0;
					q_reg <= { N {1'b0} };
				end
			else
				begin
					DFF1 <= button_in;
					DFF2 <= DFF1;
					q_reg <= q_next;
				end
		end
	
//// counter control
	always @ ( posedge clock )
		begin
			if(q_reg[N-1] == 1'b1)
					DB_out <= DFF2;
			else
					DB_out <= DB_out;
		end

	endmodule


