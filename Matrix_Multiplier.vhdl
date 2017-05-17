-------------------------------------------------------------------------------
-- Copyright (C) 2009-2012 Chris McClelland
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Lesser General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU Lesser General Public License for more details.
--
-- You should have received a copy of the GNU Lesser General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.
-------------------------------------------------------------------------------
-- Additional changes/comments by Cristinel Ababei, August 23 2012:	 
--
-- From the host, writes to R0 are simply displayed on the Atlys board's 
-- eight LEDs. Reads from R0 return the state of the board's eight slide 
-- switches. Writes to R1 and R2 are registered and may be read back. 
-- The circuit implemented on the FPGA simply multiplies the R1 with R2 
-- and places the result in R3. Only reads, from host side, are allowed 
-- from from R3; that is an attempt to write into R3 will have no effect.
-- When you input, from host side, data into R1 and R2, data should
-- represent numbers that can be represented on 4 bits only. Because
-- data will have to be input (will be done via the flcli application)
-- in hex, writing for example 07 or A7 into R1 will have the same effect 
-- as writing 07 because the four MSB will be discarded inside the
-- VHDL application on FPGA.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use IEEE.STD_LOGIC_UNSIGNED.ALL;				--needed for arithmetic and relation operations for vectors	

entity matrix_multiplier is
	port(
		-- FX2 interface -----------------------------------------------------------------------------
		fx2Clk_in     : in    std_logic;                    -- 48MHz clock from FX2
		fx2Addr_out   : out   std_logic_vector(1 downto 0); -- select FIFO: "10" for EP6OUT, "11" for EP8IN
		fx2Data_io    : inout std_logic_vector(7 downto 0); -- 8-bit data to/from FX2

		-- When EP6OUT selected:
		fx2Read_out   : out   std_logic;                    -- asserted (active-low) when reading from FX2
		fx2OE_out     : out   std_logic;                    -- asserted (active-low) to tell FX2 to drive bus
		fx2GotData_in : in    std_logic;                    -- asserted (active-high) when FX2 has data for us

		-- When EP8IN selected:
		fx2Write_out  : out   std_logic;                    -- asserted (active-low) when writing to FX2
		fx2GotRoom_in : in    std_logic;                    -- asserted (active-high) when FX2 has room for more data from us
		fx2PktEnd_out : out   std_logic;                    -- asserted (active-low) when a host read needs to be committed early

		-- Onboard peripherals -----------------------------------------------------------------------
		led_out       : out   std_logic_vector(7 downto 0) -- eight LEDs
	);
end matrix_multiplier;

architecture behavioural of matrix_multiplier is
		------------- Begin Cut here for COMPONENT Declaration ------ COMP_TAG
	COMPONENT row_ram
	  PORT (
		 clka : IN STD_LOGIC;
		 ena : IN STD_LOGIC;
		 wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
		 addra : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		 dina : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
		 douta : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
		 clkb : IN STD_LOGIC;
		 enb : IN STD_LOGIC;
		 web : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
		 addrb : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
		 dinb : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
		 doutb : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
	  );
	END COMPONENT;
	-- COMP_TAG_END ------ End COMPONENT Declaration ------------
	
		------------- Begin Cut here for COMPONENT Declaration ------ COMP_TAG
	COMPONENT matrix_ram
	  PORT (
		 clka : IN STD_LOGIC;
		 ena : IN STD_LOGIC;
		 wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
		 addra : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
		 dina : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
		 douta : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
		 clkb : IN STD_LOGIC;
		 enb : IN STD_LOGIC;
		 web : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
		 addrb : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
		 dinb : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
		 doutb : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
	  );
	END COMPONENT;
	-- COMP_TAG_END ------ End COMPONENT Declaration ------------
	
	COMPONENT mac
	PORT(
		a : IN std_logic_vector(7 downto 0);
		b : IN std_logic_vector(7 downto 0);
		clk : IN std_logic;
		rst : IN std_logic;          
		c : OUT std_logic_vector(7 downto 0)				---output c = acc (In every clk cycle acc += a*b)
		);
	END COMPONENT;
	
	-- Channel read/write interface -----------------------------------------------------------------
	signal chanAddr  : std_logic_vector(6 downto 0);  -- the selected channel (0-127)

	-- Host >> FPGA pipe:
	signal h2fData   : std_logic_vector(7 downto 0);  -- data lines used when the host writes to a channel
	signal h2fValid  : std_logic;                     -- '1' means "on the next clock rising edge, please accept the data on h2fData"
	signal h2fReady  : std_logic;                     -- channel logic can drive this low to say "I'm not ready for more data yet"

	-- Host << FPGA pipe:
	signal f2hData   : std_logic_vector(7 downto 0);  -- data lines used when the host reads from a channel
	signal f2hValid  : std_logic;                     -- channel logic can drive this low to say "I don't have data ready for you"
	signal f2hReady  : std_logic;                     -- '1' means "on the next clock rising edge, put your next byte of data on f2hData"
	-- ----------------------------------------------------------------------------------------------

	-- Needed so that the comm_fpga_fx2 module can drive both fx2Read_out and fx2OE_out
	signal fx2Read                 : std_logic;

	-- Initialisation for both ports of RAM of 16 RAMs for A and one RAM each for B and C
			-------RAM 1 --------------
	signal addra1       : std_logic_vector(3 downto 0)  := "0000";
	signal addrb1       : std_logic_vector(3 downto 0)  := "0000";
	
	signal ena1                     : std_logic  :='1';
	signal enb1                     : std_logic  :='1';
	
	signal wea1                     : std_logic_vector(0 downto 0)  :="0";
	signal web1                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina1,dinb1					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta1,doutb1					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 2 --------------
	signal addra2       : std_logic_vector(3 downto 0)  := "0000";
	signal addrb2       : std_logic_vector(3 downto 0)  := "0000";
	
	signal ena2                     : std_logic  :='1';
	signal enb2                     : std_logic  :='1';
	
	signal wea2                     : std_logic_vector(0 downto 0)  :="0";
	signal web2                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina2,dinb2					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta2,doutb2					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 3 --------------
	signal addra3       : std_logic_vector(3 downto 0)  := "0000";
	signal addrb3       : std_logic_vector(3 downto 0)  := "0000";
	
	signal ena3                     : std_logic  :='1';
	signal enb3                     : std_logic  :='1';
	
	signal wea3                     : std_logic_vector(0 downto 0)  :="0";
	signal web3                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina3,dinb3					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta3,doutb3					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 4 --------------
	signal addra4       : std_logic_vector(3 downto 0)  := "0000";
	signal addrb4       : std_logic_vector(3 downto 0)  := "0000";
	
	signal ena4                     : std_logic  :='1';
	signal enb4                     : std_logic  :='1';
	
	signal wea4                     : std_logic_vector(0 downto 0)  :="0";
	signal web4                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina4,dinb4					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta4,doutb4					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 5 --------------
	signal addra5       : std_logic_vector(3 downto 0)  := "0000";
	signal addrb5       : std_logic_vector(3 downto 0)  := "0000";
	
	signal ena5                     : std_logic  :='1';
	signal enb5                     : std_logic  :='1';
	
	signal wea5                     : std_logic_vector(0 downto 0)  :="0";
	signal web5                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina5,dinb5					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta5,doutb5					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 6 --------------
	signal addra6       : std_logic_vector(3 downto 0)  := "0000";
	signal addrb6       : std_logic_vector(3 downto 0)  := "0000";
	
	signal ena6                     : std_logic  :='1';
	signal enb6                     : std_logic  :='1';
	
	signal wea6                     : std_logic_vector(0 downto 0)  :="0";
	signal web6                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina6,dinb6					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta6,doutb6					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 7 --------------
	signal addra7       : std_logic_vector(3 downto 0)  := "0000";
	signal addrb7       : std_logic_vector(3 downto 0)  := "0000";
	
	signal ena7                     : std_logic  :='1';
	signal enb7                     : std_logic  :='1';
	
	signal wea7                     : std_logic_vector(0 downto 0)  :="0";
	signal web7                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina7,dinb7					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta7,doutb7					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 8 --------------
	signal addra8       : std_logic_vector(3 downto 0)  := "0000";
	signal addrb8       : std_logic_vector(3 downto 0)  := "0000";
	
	signal ena8                     : std_logic  :='1';
	signal enb8                     : std_logic  :='1';
	
	signal wea8                     : std_logic_vector(0 downto 0)  :="0";
	signal web8                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina8,dinb8					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta8,doutb8					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 9 --------------
	signal addra9       : std_logic_vector(3 downto 0)  := "0000";
	signal addrb9       : std_logic_vector(3 downto 0)  := "0000";
	
	signal ena9                     : std_logic  :='1';
	signal enb9                     : std_logic  :='1';
	
	signal wea9                     : std_logic_vector(0 downto 0)  :="0";
	signal web9                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina9,dinb9					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta9,doutb9					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 10 --------------
	signal addra10       : std_logic_vector(3 downto 0)  := "0000";
	signal addrb10       : std_logic_vector(3 downto 0)  := "0000";
	
	signal ena10                     : std_logic  :='1';
	signal enb10                     : std_logic  :='1';
	
	signal wea10                     : std_logic_vector(0 downto 0)  :="0";
	signal web10                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina10,dinb10					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta10,doutb10					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 11 --------------
	signal addra11       : std_logic_vector(3 downto 0)  := "0000";
	signal addrb11       : std_logic_vector(3 downto 0)  := "0000";
	
	signal ena11                     : std_logic  :='1';
	signal enb11                     : std_logic  :='1';
	
	signal wea11                     : std_logic_vector(0 downto 0)  :="0";
	signal web11                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina11,dinb11					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta11,doutb11					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 12 --------------
	signal addra12       : std_logic_vector(3 downto 0)  := "0000";
	signal addrb12       : std_logic_vector(3 downto 0)  := "0000";
	
	signal ena12                     : std_logic  :='1';
	signal enb12                     : std_logic  :='1';
	
	signal wea12                     : std_logic_vector(0 downto 0)  :="0";
	signal web12                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina12,dinb12					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta12,doutb12					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 13 --------------
	signal addra13       : std_logic_vector(3 downto 0)  := "0000";
	signal addrb13       : std_logic_vector(3 downto 0)  := "0000";
	
	signal ena13                     : std_logic  :='1';
	signal enb13                     : std_logic  :='1';
	
	signal wea13                     : std_logic_vector(0 downto 0)  :="0";
	signal web13                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina13,dinb13					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta13,doutb13					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 14 --------------
	signal addra14       : std_logic_vector(3 downto 0)  := "0000";
	signal addrb14       : std_logic_vector(3 downto 0)  := "0000";
	
	signal ena14                     : std_logic  :='1';
	signal enb14                     : std_logic  :='1';
	
	signal wea14                     : std_logic_vector(0 downto 0)  :="0";
	signal web14                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina14,dinb14					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta14,doutb14					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 15 --------------
	signal addra15       : std_logic_vector(3 downto 0)  := "0000";
	signal addrb15       : std_logic_vector(3 downto 0)  := "0000";
	
	signal ena15                     : std_logic  :='1';
	signal enb15                     : std_logic  :='1';
	
	signal wea15                     : std_logic_vector(0 downto 0)  :="0";
	signal web15                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina15,dinb15					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta15,doutb15					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 16 --------------
	signal addra16       : std_logic_vector(3 downto 0)  := "0000";
	signal addrb16       : std_logic_vector(3 downto 0)  := "0000";
	
	signal ena16                     : std_logic  :='1';
	signal enb16                     : std_logic  :='1';
	
	signal wea16                     : std_logic_vector(0 downto 0)  :="0";
	signal web16                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina16,dinb16					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta16,doutb16					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM for B --------------
	signal addra17       : std_logic_vector(7 downto 0)  := "00000000";
	signal addrb17       : std_logic_vector(7 downto 0)  := "00000000";
	
	signal ena17                     : std_logic  :='1';
	signal enb17                     : std_logic  :='1';
	
	signal wea17                     : std_logic_vector(0 downto 0)  :="0";
	signal web17                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina17,dinb17					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta17,doutb17					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM for C--------------
	signal addra18       : std_logic_vector(7 downto 0)  := "00000000";
	signal addrb18       : std_logic_vector(7 downto 0)  := "00000000";
	
	signal ena18                     : std_logic  :='1';
	signal enb18                     : std_logic  :='1';
	
	signal wea18                     : std_logic_vector(0 downto 0)  :="0";
	signal web18                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina18,dinb18					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta18,doutb18					 : std_logic_vector(7 downto 0)  := x"00";
	
	-- Registers implementing the channels
	signal reg0, reg0_next         : std_logic_vector(7 downto 0)  := x"00";
	--enable computing C
	signal multiply_en                     : std_logic  :='0';
	
	--16 MACs--
	signal b       : std_logic_vector(7 downto 0)  := "00000000";    --common signal broadcast to all MACs
	signal rst       : std_logic  := '0';									  --common reset for all MACs
	--MAC 1
	signal a1       : std_logic_vector(7 downto 0)  := "00000000";
	signal c1       : std_logic_vector(7 downto 0)  := "00000000";
	--MAC 2
	signal a2       : std_logic_vector(7 downto 0)  := "00000000";
	signal c2       : std_logic_vector(7 downto 0)  := "00000000";
	--MAC 3
	signal a3       : std_logic_vector(7 downto 0)  := "00000000";
	signal c3       : std_logic_vector(7 downto 0)  := "00000000";
	--MAC 4
	signal a4       : std_logic_vector(7 downto 0)  := "00000000";
	signal c4       : std_logic_vector(7 downto 0)  := "00000000";
	--MAC 5
	signal a5       : std_logic_vector(7 downto 0)  := "00000000";
	signal c5       : std_logic_vector(7 downto 0)  := "00000000";
	--MAC 6
	signal a6       : std_logic_vector(7 downto 0)  := "00000000";
	signal c6       : std_logic_vector(7 downto 0)  := "00000000";
	--MAC 7
	signal a7       : std_logic_vector(7 downto 0)  := "00000000";
	signal c7       : std_logic_vector(7 downto 0)  := "00000000";
	--MAC 8
	signal a8       : std_logic_vector(7 downto 0)  := "00000000";
	signal c8       : std_logic_vector(7 downto 0)  := "00000000";
	--MAC 9
	signal a9       : std_logic_vector(7 downto 0)  := "00000000";
	signal c9       : std_logic_vector(7 downto 0)  := "00000000";
	--MAC 10
	signal a10       : std_logic_vector(7 downto 0)  := "00000000";
	signal c10       : std_logic_vector(7 downto 0)  := "00000000";
	--MAC 11
	signal a11       : std_logic_vector(7 downto 0)  := "00000000";
	signal c11       : std_logic_vector(7 downto 0)  := "00000000";
	--MAC 12
	signal a12       : std_logic_vector(7 downto 0)  := "00000000";
	signal c12       : std_logic_vector(7 downto 0)  := "00000000";
	--MAC 13
	signal a13       : std_logic_vector(7 downto 0)  := "00000000";
	signal c13       : std_logic_vector(7 downto 0)  := "00000000";
	--MAC 14
	signal a14       : std_logic_vector(7 downto 0)  := "00000000";
	signal c14       : std_logic_vector(7 downto 0)  := "00000000";
	--MAC 15
	signal a15       : std_logic_vector(7 downto 0)  := "00000000";
	signal c15       : std_logic_vector(7 downto 0)  := "00000000";
	--MAC 16
	signal a16       : std_logic_vector(7 downto 0)  := "00000000";
	signal c16       : std_logic_vector(7 downto 0)  := "00000000";
	
begin													-- BEGIN_SNIPPET(registers)
	--16 RAMs for rows of matrix A
		------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	row1 : row_ram
	  PORT MAP (
		 clka => fx2Clk_in,
		 ena => ena1,
		 wea => wea1,
		 addra => addra1,
		 dina => dina1,
		 douta => douta1,
		 clkb => fx2Clk_in,
		 enb => enb1,
		 web => web1,
		 addrb => addrb1,
		 dinb => dinb1,
		 doutb => doutb1
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------
		------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	row2 : row_ram
	  PORT MAP (
		 clka => fx2Clk_in,
		 ena => ena2,
		 wea => wea2,
		 addra => addra2,
		 dina => dina2,
		 douta => douta2,
		 clkb => fx2Clk_in,
		 enb => enb2,
		 web => web2,
		 addrb => addrb2,
		 dinb => dinb2,
		 doutb => doutb2
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------
		------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	row3 : row_ram
	  PORT MAP (
		 clka => fx2Clk_in,
		 ena => ena3,
		 wea => wea3,
		 addra => addra3,
		 dina => dina3,
		 douta => douta3,
		 clkb => fx2Clk_in,
		 enb => enb3,
		 web => web3,
		 addrb => addrb3,
		 dinb => dinb3,
		 doutb => doutb3
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------
		------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	row4 : row_ram
	  PORT MAP (
		 clka => fx2Clk_in,
		 ena => ena4,
		 wea => wea4,
		 addra => addra4,
		 dina => dina4,
		 douta => douta4,
		 clkb => fx2Clk_in,
		 enb => enb4,
		 web => web4,
		 addrb => addrb4,
		 dinb => dinb4,
		 doutb => doutb4
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------
		------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	row5 : row_ram
	  PORT MAP (
		 clka => fx2Clk_in,
		 ena => ena5,
		 wea => wea5,
		 addra => addra5,
		 dina => dina5,
		 douta => douta5,
		 clkb => fx2Clk_in,
		 enb => enb5,
		 web => web5,
		 addrb => addrb5,
		 dinb => dinb5,
		 doutb => doutb5
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------
		------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	row6 : row_ram
	  PORT MAP (
		 clka => fx2Clk_in,
		 ena => ena6,
		 wea => wea6,
		 addra => addra6,
		 dina => dina6,
		 douta => douta6,
		 clkb => fx2Clk_in,
		 enb => enb6,
		 web => web6,
		 addrb => addrb6,
		 dinb => dinb6,
		 doutb => doutb6
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------
		------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	row7 : row_ram
	  PORT MAP (
		 clka => fx2Clk_in,
		 ena => ena7,
		 wea => wea7,
		 addra => addra7,
		 dina => dina7,
		 douta => douta7,
		 clkb => fx2Clk_in,
		 enb => enb7,
		 web => web7,
		 addrb => addrb7,
		 dinb => dinb7,
		 doutb => doutb7
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------
		------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	row8 : row_ram
	  PORT MAP (
		 clka => fx2Clk_in,
		 ena => ena8,
		 wea => wea8,
		 addra => addra8,
		 dina => dina8,
		 douta => douta8,
		 clkb => fx2Clk_in,
		 enb => enb8,
		 web => web8,
		 addrb => addrb8,
		 dinb => dinb8,
		 doutb => doutb8
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------
		------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	row9 : row_ram
	  PORT MAP (
		 clka => fx2Clk_in,
		 ena => ena9,
		 wea => wea9,
		 addra => addra9,
		 dina => dina9,
		 douta => douta9,
		 clkb => fx2Clk_in,
		 enb => enb9,
		 web => web9,
		 addrb => addrb9,
		 dinb => dinb9,
		 doutb => doutb9
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------
		------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	row10 : row_ram
	  PORT MAP (
		 clka => fx2Clk_in,
		 ena => ena10,
		 wea => wea10,
		 addra => addra10,
		 dina => dina10,
		 douta => douta10,
		 clkb => fx2Clk_in,
		 enb => enb10,
		 web => web10,
		 addrb => addrb10,
		 dinb => dinb10,
		 doutb => doutb10
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------
		------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	row11 : row_ram
	  PORT MAP (
		 clka => fx2Clk_in,
		 ena => ena11,
		 wea => wea11,
		 addra => addra11,
		 dina => dina11,
		 douta => douta11,
		 clkb => fx2Clk_in,
		 enb => enb11,
		 web => web11,
		 addrb => addrb11,
		 dinb => dinb11,
		 doutb => doutb11
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------
		------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	row12 : row_ram
	  PORT MAP (
		 clka => fx2Clk_in,
		 ena => ena12,
		 wea => wea12,
		 addra => addra12,
		 dina => dina12,
		 douta => douta12,
		 clkb => fx2Clk_in,
		 enb => enb12,
		 web => web12,
		 addrb => addrb12,
		 dinb => dinb12,
		 doutb => doutb12
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------
		------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	row13 : row_ram
	  PORT MAP (
		 clka => fx2Clk_in,
		 ena => ena13,
		 wea => wea13,
		 addra => addra13,
		 dina => dina13,
		 douta => douta13,
		 clkb => fx2Clk_in,
		 enb => enb13,
		 web => web13,
		 addrb => addrb13,
		 dinb => dinb13,
		 doutb => doutb13
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------
		------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	row14 : row_ram
	  PORT MAP (
		 clka => fx2Clk_in,
		 ena => ena14,
		 wea => wea14,
		 addra => addra14,
		 dina => dina14,
		 douta => douta14,
		 clkb => fx2Clk_in,
		 enb => enb14,
		 web => web14,
		 addrb => addrb14,
		 dinb => dinb14,
		 doutb => doutb14
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------
		------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	row15 : row_ram
	  PORT MAP (
		 clka => fx2Clk_in,
		 ena => ena15,
		 wea => wea15,
		 addra => addra15,
		 dina => dina15,
		 douta => douta15,
		 clkb => fx2Clk_in,
		 enb => enb15,
		 web => web15,
		 addrb => addrb15,
		 dinb => dinb15,
		 doutb => doutb15
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------
		------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	row16 : row_ram
	  PORT MAP (
		 clka => fx2Clk_in,
		 ena => ena16,
		 wea => wea16,
		 addra => addra16,
		 dina => dina16,
		 douta => douta16,
		 clkb => fx2Clk_in,
		 enb => enb16,
		 web => web16,
		 addrb => addrb16,
		 dinb => dinb16,
		 doutb => doutb16
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------
	
	--Matrix B
	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	matrixb: matrix_ram
	  PORT MAP (
		 clka => fx2Clk_in,
		 ena => ena17,
		 wea => wea17,
		 addra => addra17,
		 dina => dina17,
		 douta => douta17,
		 clkb => fx2Clk_in,
		 enb => enb17,
		 web => web17,
		 addrb => addrb17,
		 dinb => dinb17,
		 doutb => doutb17
  );
-- INST_TAG_END ------ End INSTANTIATION Template ------------

	--Matrix C
	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	matrixc: matrix_ram
	  PORT MAP (
		 clka => fx2Clk_in,
		 ena => ena18,
		 wea => wea18,
		 addra => addra18,
		 dina => dina18,
		 douta => douta18,
		 clkb => fx2Clk_in,
		 enb => enb18,
		 web => web18,
		 addrb => addrb18,
		 dinb => dinb18,
		 doutb => doutb18
  );
-- INST_TAG_END ------ End INSTANTIATION Template ------------
	
	-- 16 MACs one for each row
	mac1: mac 
	PORT MAP(
		a => a1,
		b => b,
		clk => fx2Clk_in,
		rst => rst,
		c => c1
	);
	mac2: mac 
	PORT MAP(
		a => a2,
		b => b,
		clk => fx2Clk_in,
		rst => rst,
		c => c2
	);
	mac3: mac 
	PORT MAP(
		a => a3,
		b => b,
		clk => fx2Clk_in,
		rst => rst,
		c => c3
	);
	mac4: mac 
	PORT MAP(
		a => a4,
		b => b,
		clk => fx2Clk_in,
		rst => rst,
		c => c4
	);
	mac5: mac 
	PORT MAP(
		a => a5,
		b => b,
		clk => fx2Clk_in,
		rst => rst,
		c => c5
	);
	mac6: mac 
	PORT MAP(
		a => a6,
		b => b,
		clk => fx2Clk_in,
		rst => rst,
		c => c6
	);
	mac7: mac 
	PORT MAP(
		a => a7,
		b => b,
		clk => fx2Clk_in,
		rst => rst,
		c => c7
	);
	mac8: mac 
	PORT MAP(
		a => a8,
		b => b,
		clk => fx2Clk_in,
		rst => rst,
		c => c8
	);
	mac9: mac 
	PORT MAP(
		a => a9,
		b => b,
		clk => fx2Clk_in,
		rst => rst,
		c => c9
	);
	mac10: mac 
	PORT MAP(
		a => a10,
		b => b,
		clk => fx2Clk_in,
		rst => rst,
		c => c10
	);
	mac11: mac 
	PORT MAP(
		a => a11,
		b => b,
		clk => fx2Clk_in,
		rst => rst,
		c => c11
	);
	mac12: mac 
	PORT MAP(
		a => a12,
		b => b,
		clk => fx2Clk_in,
		rst => rst,
		c => c12
	);
	mac13: mac 
	PORT MAP(
		a => a13,
		b => b,
		clk => fx2Clk_in,
		rst => rst,
		c => c13
	);
	mac14: mac 
	PORT MAP(
		a => a14,
		b => b,
		clk => fx2Clk_in,
		rst => rst,
		c => c14
	);
	mac15: mac 
	PORT MAP(
		a => a15,
		b => b,
		clk => fx2Clk_in,
		rst => rst,
		c => c15
	);
	mac16: mac 
	PORT MAP(
		a => a16,
		b => b,
		clk => fx2Clk_in,
		rst => rst,
		c => c16
	);
	-- Infer registers
	process(fx2Clk_in)
	begin
		if ( rising_edge(fx2Clk_in) ) then
			reg0 <= reg0_next;
			--FSM 3 states 00 01 02(in hex).
			if( reg0 = x"00") then
				--read A and B
				--for matrix A (16 row_rams)
				--increment address for row_rams when channel write performed--
				--row_ram 1
				if(chanAddr = "0000001" and h2fValid = '1') then
					addra1 <= addra1 + "0001";
				end if;
				--row_ram 2
				if(chanAddr = "0000001" and h2fValid = '1') then
					addra2 <= addra2 + "0001";
				end if;
				--row_ram 3
				if(chanAddr = "0000001" and h2fValid = '1') then
					addra3 <= addra3 + "0001";
				end if;
				--row_ram 4
				if(chanAddr = "0000001" and h2fValid = '1') then
					addra4 <= addra4 + "0001";
				end if;
				--row_ram 5
				if(chanAddr = "0000001" and h2fValid = '1') then
					addra5 <= addra5 + "0001";
				end if;
				--row_ram 6
				if(chanAddr = "0000001" and h2fValid = '1') then
					addra6 <= addra6 + "0001";
				end if;
				--row_ram 7
				if(chanAddr = "0000001" and h2fValid = '1') then
					addra7 <= addra7 + "0001";
				end if;
				--row_ram 8
				if(chanAddr = "0000001" and h2fValid = '1') then
					addra8 <= addra8 + "0001";
				end if;
				--row_ram 9
				if(chanAddr = "0000001" and h2fValid = '1') then
					addra9 <= addra9 + "0001";
				end if;
				--row_ram 10
				if(chanAddr = "0000001" and h2fValid = '1') then
					addra10 <= addra10 + "0001";
				end if;
				--row_ram 11
				if(chanAddr = "0000001" and h2fValid = '1') then
					addra11 <= addra11 + "0001";
				end if;
				--row_ram 12
				if(chanAddr = "0000001" and h2fValid = '1') then
					addra12 <= addra12 + "0001";
				end if;
				--row_ram 13
				if(chanAddr = "0000001" and h2fValid = '1') then
					addra13 <= addra13 + "0001";
				end if;
				--row_ram 14
				if(chanAddr = "0000001" and h2fValid = '1') then
					addra14 <= addra14 + "0001";
				end if;
				--row_ram 15
				if(chanAddr = "0000001" and h2fValid = '1') then
					addra15 <= addra15 + "0001";
				end if;
				--row_ram 16
				if(chanAddr = "0000001" and h2fValid = '1') then
					addra16 <= addra16 + "0001";
				end if;
				--Matrix B
				if(chanAddr = "0000001" and h2fValid = '1') then
					addra17 <= addra17 + "00000001";
				end if;
			elsif( reg0 = x"01") then
				--reset addresses to 0 for  all 16 rows of A and matrix B
				addra1 <= "0000";
				addra2 <= "0000";
				addra3 <= "0000";
				addra4 <= "0000";
				addra5 <= "0000";
				addra6 <= "0000";
				addra7 <= "0000";
				addra8 <= "0000";
				addra9 <= "0000";
				addra10 <= "0000";
				addra11 <= "0000";
				addra12 <= "0000";
				addra13 <= "0000";
				addra14 <= "0000";
				addra15 <= "0000";
				addra16 <= "0000";
				addra17 <= "00000000";
				multiply_en <= '1';
			elsif( reg0 = x"02") then
				--Calculate C
				if(multiply_en = '1' or not(addra18 = x"00")) then 
					--if(addra18 mod 16 == 0 ) write to c and move ahead
					
					--end condition .. C calculated when addr18 becomes ff in next cycle stop
					if(addra18 = x"ff")then
						multiply_en <= '0';
						reg0 <= x"03";	--next state of machine signifying pc can read data as C calculated
					end if;
				end if;
			end if;
		end if;
	end process;

	-- Drive register input for each channel when the host is writing
	--this register stores the state of machine
	reg0_next <= h2fData when chanAddr = "0000000" and h2fValid = '1' else reg0;
	
	--write enable on and h2fData to din of ram when channel has data from host
	wea1 <="1" when chanAddr = "0000001" and h2fValid = '1' else "0";
	dina1 <= h2fData when chanAddr = "0000001" and h2fValid = '1' else "00000000";
	wea2 <="1" when chanAddr = "0000010" and h2fValid = '1' else "0";
	dina2 <= h2fData when chanAddr = "0000010" and h2fValid = '1' else "00000000";
	wea3 <="1" when chanAddr = "0000011" and h2fValid = '1' else "0";
	dina3 <= h2fData when chanAddr = "0000011" and h2fValid = '1' else "00000000";
	wea4 <="1" when chanAddr = "0000100" and h2fValid = '1' else "0";
	dina4 <= h2fData when chanAddr = "0000100" and h2fValid = '1' else "00000000";
	wea5 <="1" when chanAddr = "0000101" and h2fValid = '1' else "0";
	dina5 <= h2fData when chanAddr = "0000101" and h2fValid = '1' else "00000000";
	wea6 <="1" when chanAddr = "0000110" and h2fValid = '1' else "0";
	dina6 <= h2fData when chanAddr = "0000110" and h2fValid = '1' else "00000000";
	wea7 <="1" when chanAddr = "0000111" and h2fValid = '1' else "0";
	dina7 <= h2fData when chanAddr = "0000111" and h2fValid = '1' else "00000000";
	wea8 <="1" when chanAddr = "0001000" and h2fValid = '1' else "0";
	dina8 <= h2fData when chanAddr = "0001000" and h2fValid = '1' else "00000000";
	wea9 <="1" when chanAddr = "0001001" and h2fValid = '1' else "0";
	dina9 <= h2fData when chanAddr = "0001001" and h2fValid = '1' else "00000000";
	wea10 <="1" when chanAddr = "0010000" and h2fValid = '1' else "0";
	dina10 <= h2fData when chanAddr = "0010000" and h2fValid = '1' else "00000000";
	wea11 <="1" when chanAddr = "0010001" and h2fValid = '1' else "0";
	dina11 <= h2fData when chanAddr = "0010001" and h2fValid = '1' else "00000000";
	wea12 <="1" when chanAddr = "0010010" and h2fValid = '1' else "0";
	dina12 <= h2fData when chanAddr = "0010010" and h2fValid = '1' else "00000000";
	wea13 <="1" when chanAddr = "0010011" and h2fValid = '1' else "0";
	dina13 <= h2fData when chanAddr = "0010011" and h2fValid = '1' else "00000000";
	wea14 <="1" when chanAddr = "0010100" and h2fValid = '1' else "0";
	dina14 <= h2fData when chanAddr = "0010100" and h2fValid = '1' else "00000000";
	wea15 <="1" when chanAddr = "0010101" and h2fValid = '1' else "0";
	dina15 <= h2fData when chanAddr = "0010101" and h2fValid = '1' else "00000000";
	wea16 <="1" when chanAddr = "0010110" and h2fValid = '1' else "0";
	dina16 <= h2fData when chanAddr = "0010110" and h2fValid = '1' else "00000000";
	wea17 <="1" when chanAddr = "0010111" and h2fValid = '1' else "0";
	dina17 <= h2fData when chanAddr = "0010111" and h2fValid = '1' else "00000000";
	
	-- Select values to return for each channel when the host is reading
	with chanAddr select f2hData <=
		reg0 	when "0000000",
		douta18 when "0011000",
		x"00" 			when others;
	
	--DO NOT CHANGE ANYTHING BELOW
	-- Assert that there's always data for reading, and always room for writing
	f2hValid <= '1';
	h2fReady <= '1';								--END_SNIPPET(registers)

	-- CommFPGA module
	fx2Read_out <= fx2Read;
	fx2OE_out <= fx2Read;
	fx2Addr_out(1) <= '1';  -- Use EP6OUT/EP8IN, not EP2OUT/EP4IN.
	comm_fpga_fx2 : entity work.comm_fpga_fx2
		port map(
			-- FX2 interface
			fx2Clk_in      => fx2Clk_in,
			fx2FifoSel_out => fx2Addr_out(0),
			fx2Data_io     => fx2Data_io,
			fx2Read_out    => fx2Read,
			fx2GotData_in  => fx2GotData_in,
			fx2Write_out   => fx2Write_out,
			fx2GotRoom_in  => fx2GotRoom_in,
			fx2PktEnd_out  => fx2PktEnd_out,

			-- Channel read/write interface
			chanAddr_out   => chanAddr,
			h2fData_out    => h2fData,
			h2fValid_out   => h2fValid,
			h2fReady_in    => h2fReady,
			f2hData_in     => f2hData,
			f2hValid_in    => f2hValid,
			f2hReady_out   => f2hReady
		);

	-- LEDs
	led_out <= reg0;
end behavioural;
