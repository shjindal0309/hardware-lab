`timescale 1ns / 1ps

module functions
   (output[7:0] sum,
    input[4:0]  temp,
	 input[1:0] selected,
	 input b,
	 input RESET,
	 input myClk,
	 input a,
	 input c,
	 input d);
	 
	reg[4:0] n = 4'b00001;
	reg[1:0] q;
	reg[4:0] count = 0;
	reg[4:0] inp[0:9];
	reg[13:0] ans = 14'b0000000000000;
	reg[15:0] temp2;
	
DeBounce bd(myClk, 1'b1, a, myNewClk);

always @(posedge myNewClk)
	begin
		if( count <= n)
			case (count)
				5'b00000:
					n <= temp;
				5'b00001:
					inp[0] <= temp;
				5'b00010:
					inp[1] <= temp;
				5'b00011:
					inp[2] <= temp;
				5'b00100:
					inp[3] <= temp;
				5'b00101:
					inp[4] <= temp;
				5'b00110:
					inp[5] <= temp;
				5'b00111:
					inp[6] <= temp;
				5'b01000:
					inp[7] <= temp;
				5'b01001:
					inp[8] <= temp;
				5'b01010:
					inp[9] <= temp;
			endcase
	end

always @(negedge myNewClk)
	begin
	count = count + 1;
   end

reg[13:0] total;
reg[5:0] avg;
reg[13:0] sumsquare;
reg[13:0] variance = 14'b00000000000000;
integer i;

always @(posedge b)
	begin
	//total = (inp[0] + inp[1] + inp[2] + inp[3] + inp[4] + inp[5] + inp[6] + inp[7] + inp[8] + inp[9]);
	//avg = total / n;
	//sumsquare = (inp[0]*inp[0] + inp[1]*inp[1] + inp[2]*inp[2] + inp[3]*inp[3] + inp[4]*inp[4] + inp[5]*inp[5] + inp[6]*inp[6] + inp[7]*inp[7] + inp[8]*inp[8] + inp[9]*inp[9]);
	case (selected)
			2'b00:
				begin
				total = 0;
				for (i=0; i<10; i=i+1)
					begin
					total = total + inp[i];
					end
				temp2 = total;			
				end
			2'b01:
				begin
				avg = 0;
				for (i=0; i<10; i=i+1)
					begin
					avg = avg + inp[i];
					end
				avg = avg/n;
				temp2 = avg;			
				end
			2'b10:
				begin
				sumsquare=0;
				for (i=0; i<10; i=i+1)
					begin
					sumsquare = sumsquare + (inp[i]*inp[i]);
					end
				temp2 = sumsquare;
				
				end				
			2'b11:
				begin
				variance = 0;
				for (i=0; i<10; i=i+1)
					begin
					avg = avg + inp[i];
					end
				avg = avg/n;	
				for(i=0; i<10; i=i+1)
				begin
				if(i<n)
					begin
						if(inp[i]>avg)
						variance = variance + (inp[i]-avg)*(inp[i]-avg);
						else
						variance = variance + (avg-inp[i])*(avg-inp[i]);
					end
				end
				
				variance = variance/n;
				
				for(i=0; i<33; i=i+1)
				begin
				if( (i*i < variance ||  i*i == variance) )
					temp2 = i;
				end
				
				//temp2 = variance;
				end
	endcase
	end
	reg[7:0] sumTemp;
	
always @(*)
	if(c==0)
	begin
	for ( i=0; i<8; i=i+1)
		sumTemp[i] = temp2[i];
	end
	else
	begin
	for ( i=0; i<8; i=i+1)
		sumTemp[i] = temp2[i+8];
	end

/*
always @(posedge d)
	begin
	for ( i=0; i<8; i=i+1)
		sumTemp[i] = temp2[i+8];
	end
*/	
assign {sum} = sumTemp;

endmodule

module  DeBounce 
	(
	input 			clk, n_reset, button_in,				// inputs
	output reg 	DB_out													// output
	);
//// ---------------- internal constants --------------
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
	always @ ( posedge clk )
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
	always @ ( posedge clk )
		begin
			if(q_reg[N-1] == 1'b1)
					DB_out <= DFF2;
			else
					DB_out <= DB_out;
		end

	endmodule


