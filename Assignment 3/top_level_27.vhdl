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


entity top_level is
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
		led_out       : out   std_logic_vector(7 downto 0); -- eight LEDs
		slide_sw_in   : in    std_logic_vector(7 downto 0)  -- eight slide switches
	);
end top_level;

architecture behavioural of top_level is
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

	------------- Begin Cut here for COMPONENT Declaration ------ COMP_TAG
	COMPONENT bram
	  PORT (
		 clka : IN STD_LOGIC;
		 wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
		 addra : IN STD_LOGIC_VECTOR(12 DOWNTO 0);
		 dina : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
		 douta : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
		 clkb : IN STD_LOGIC;
		 web : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
		 addrb : IN STD_LOGIC_VECTOR(12 DOWNTO 0);
		 dinb : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
		 doutb : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
	  );
	END COMPONENT;
	-- COMP_TAG_END ------ End COMPONENT Declaration ------------

	
	------------- Begin Cut here for COMPONENT Declaration ------ COMP_TAG
COMPONENT calculated
  PORT (
    clka : IN STD_LOGIC;
    wea : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    addra : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
    dina : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    douta : OUT STD_LOGIC_VECTOR(7 DOWNTO 0)
  );
END COMPONENT;
-- COMP_TAG_END ------ End COMPONENT Declaration ------------
	

	-- Initialisation for both ports of RAM of 27 RAMs(9 RAMs for each channel of image(R,G,B)
			-------RAM 1 --------------
	signal addra1       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb1       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea1                     : std_logic_vector(0 downto 0)  :="0";
	signal web1                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina1,dinb1					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta1,doutb1					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 2 --------------
	signal addra2       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb2       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea2                     : std_logic_vector(0 downto 0)  :="0";
	signal web2                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina2,dinb2					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta2,doutb2					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 3 --------------
	signal addra3       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb3       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea3                     : std_logic_vector(0 downto 0)  :="0";
	signal web3                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina3,dinb3					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta3,doutb3					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 4 --------------
	signal addra4       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb4       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea4                     : std_logic_vector(0 downto 0)  :="0";
	signal web4                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina4,dinb4					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta4,doutb4					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 5 --------------
	signal addra5       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb5       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea5                     : std_logic_vector(0 downto 0)  :="0";
	signal web5                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina5,dinb5					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta5,doutb5					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 6 --------------
	signal addra6       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb6       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea6                     : std_logic_vector(0 downto 0)  :="0";
	signal web6                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina6,dinb6					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta6,doutb6					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 7 --------------
	signal addra7       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb7       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea7                     : std_logic_vector(0 downto 0)  :="0";
	signal web7                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina7,dinb7					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta7,doutb7					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 8 --------------
	signal addra8       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb8       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea8                     : std_logic_vector(0 downto 0)  :="0";
	signal web8                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina8,dinb8					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta8,doutb8					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 9 --------------
	signal addra9       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb9       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea9                     : std_logic_vector(0 downto 0)  :="0";
	signal web9                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina9,dinb9					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta9,doutb9					 : std_logic_vector(7 downto 0)  := x"00";

			-------RAM 11 --------------
	signal addra11       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb11       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea11                     : std_logic_vector(0 downto 0)  :="0";
	signal web11                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina11,dinb11					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta11,doutb11					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 12 --------------
	signal addra12       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb12       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea12                     : std_logic_vector(0 downto 0)  :="0";
	signal web12                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina12,dinb12					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta12,doutb12					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 13 --------------
	signal addra13       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb13       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea13                     : std_logic_vector(0 downto 0)  :="0";
	signal web13                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina13,dinb13					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta13,doutb13					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 14 --------------
	signal addra14       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb14       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea14                     : std_logic_vector(0 downto 0)  :="0";
	signal web14                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina14,dinb14					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta14,doutb14					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 15 --------------
	signal addra15       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb15       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea15                     : std_logic_vector(0 downto 0)  :="0";
	signal web15                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina15,dinb15					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta15,doutb15					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 16 --------------
	signal addra16       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb16       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea16                     : std_logic_vector(0 downto 0)  :="0";
	signal web16                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina16,dinb16					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta16,doutb16					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 17 --------------
	signal addra17       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb17       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea17                     : std_logic_vector(0 downto 0)  :="0";
	signal web17                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina17,dinb17					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta17,doutb17					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 18 --------------
	signal addra18       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb18       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea18                     : std_logic_vector(0 downto 0)  :="0";
	signal web18                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina18,dinb18					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta18,doutb18					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 19 --------------
	signal addra19       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb19       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea19                     : std_logic_vector(0 downto 0)  :="0";
	signal web19                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina19,dinb19					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta19,doutb19					 : std_logic_vector(7 downto 0)  := x"00";

			-------RAM 21 --------------
	signal addra21       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb21       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea21                     : std_logic_vector(0 downto 0)  :="0";
	signal web21                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina21,dinb21					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta21,doutb21					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 22 --------------
	signal addra22       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb22       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea22                     : std_logic_vector(0 downto 0)  :="0";
	signal web22                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina22,dinb22					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta22,doutb22					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 23 --------------
	signal addra23       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb23       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea23                     : std_logic_vector(0 downto 0)  :="0";
	signal web23                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina23,dinb23					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta23,doutb23					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 24 --------------
	signal addra24       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb24       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea24                     : std_logic_vector(0 downto 0)  :="0";
	signal web24                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina24,dinb24					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta24,doutb24					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 25 --------------
	signal addra25       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb25       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea25                     : std_logic_vector(0 downto 0)  :="0";
	signal web25                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina25,dinb25					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta25,doutb25					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 26 --------------
	signal addra26       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb26       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea26                     : std_logic_vector(0 downto 0)  :="0";
	signal web26                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina26,dinb26					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta26,doutb26					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 27 --------------
	signal addra27       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb27       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea27                     : std_logic_vector(0 downto 0)  :="0";
	signal web27                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina27,dinb27					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta27,doutb27					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 28 --------------
	signal addra28       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb28       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea28                     : std_logic_vector(0 downto 0)  :="0";
	signal web28                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina28,dinb28					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta28,doutb28					 : std_logic_vector(7 downto 0)  := x"00";
			-------RAM 29 --------------
	signal addra29       : std_logic_vector(12 downto 0)  := "0000000000000";
	signal addrb29       : std_logic_vector(12 downto 0)  := "0000000000000";
	
	signal wea29                     : std_logic_vector(0 downto 0)  :="0";
	signal web29                     : std_logic_vector(0 downto 0)  :="0";
	
	signal dina29,dinb29					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta29,doutb29					 : std_logic_vector(7 downto 0)  := x"00";

			-------RAM 31 --------------
	signal addra31       : std_logic_vector(15 downto 0)  := "0000000000000000";
	signal wea31                     : std_logic_vector(0 downto 0)  :="0";
	signal dina31				 : std_logic_vector(7 downto 0)  := x"00";
	signal douta31					 : std_logic_vector(7 downto 0)  := x"00";
	
				-------RAM 32 --------------
	signal addra32       : std_logic_vector(15 downto 0)  := "0000000000000000";
	signal wea32                     : std_logic_vector(0 downto 0)  :="0";
	signal dina32					 : std_logic_vector(7 downto 0)  := x"00";
	signal douta32				 : std_logic_vector(7 downto 0)  := x"00";

			-------RAM 33 --------------
	signal addra33       : std_logic_vector(15 downto 0)  := "0000000000000000";
	signal wea33                     : std_logic_vector(0 downto 0)  :="0";
	signal dina33			 : std_logic_vector(7 downto 0)  := x"00";
	signal douta33					 : std_logic_vector(7 downto 0)  := x"00";
	
	signal dividend   :std_logic_vector(11 downto 0)  := "000000000000";
	signal divisor   :std_logic_vector(7 downto 0)  := "00000000";
	signal ce :std_logic :='0';
	signal rfd :std_logic :='0';
	signal sclr :std_logic :='0';
	signal quotient   :std_logic_vector(11 downto 0)  := "000000000000";
	signal fractional   :std_logic_vector(7 downto 0)  := "00000000";
begin													-- BEGIN_SNIPPET(registers)
	
	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram1 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea1,
		 addra => addra1,
		 dina => dina1,
		 douta => douta1,
		 clkb => fx2Clk_in,
		 web => web1,
		 addrb => addrb1,
		 dinb => dinb1,
		 doutb => doutb1
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram2 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea2,
		 addra => addra2,
		 dina => dina2,
		 douta => douta2,
		 clkb => fx2Clk_in,
		 web => web2,
		 addrb => addrb2,
		 dinb => dinb2,
		 doutb => doutb2
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram3 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea3,
		 addra => addra3,
		 dina => dina3,
		 douta => douta3,
		 clkb => fx2Clk_in,
		 web => web3,
		 addrb => addrb3,
		 dinb => dinb3,
		 doutb => doutb3
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram4 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea4,
		 addra => addra4,
		 dina => dina4,
		 douta => douta4,
		 clkb => fx2Clk_in,
		 web => web4,
		 addrb => addrb4,
		 dinb => dinb4,
		 doutb => doutb4
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram5 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea5,
		 addra => addra5,
		 dina => dina5,
		 douta => douta5,
		 clkb => fx2Clk_in,
		 web => web5,
		 addrb => addrb5,
		 dinb => dinb5,
		 doutb => doutb5
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram6 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea6,
		 addra => addra6,
		 dina => dina6,
		 douta => douta6,
		 clkb => fx2Clk_in,
		 web => web6,
		 addrb => addrb6,
		 dinb => dinb6,
		 doutb => doutb6
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram7 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea7,
		 addra => addra7,
		 dina => dina7,
		 douta => douta7,
		 clkb => fx2Clk_in,
		 web => web7,
		 addrb => addrb7,
		 dinb => dinb7,
		 doutb => doutb7
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram8 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea8,
		 addra => addra8,
		 dina => dina8,
		 douta => douta8,
		 clkb => fx2Clk_in,
		 web => web8,
		 addrb => addrb8,
		 dinb => dinb8,
		 doutb => doutb8
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram9 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea9,
		 addra => addra9,
		 dina => dina9,
		 douta => douta9,
		 clkb => fx2Clk_in,
		 web => web9,
		 addrb => addrb9,
		 dinb => dinb9,
		 doutb => doutb9
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram11 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea11,
		 addra => addra11,
		 dina => dina11,
		 douta => douta11,
		 clkb => fx2Clk_in,
		 web => web11,
		 addrb => addrb11,
		 dinb => dinb11,
		 doutb => doutb11
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram12 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea12,
		 addra => addra12,
		 dina => dina12,
		 douta => douta12,
		 clkb => fx2Clk_in,
		 web => web12,
		 addrb => addrb12,
		 dinb => dinb12,
		 doutb => doutb12
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram13 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea13,
		 addra => addra13,
		 dina => dina13,
		 douta => douta13,
		 clkb => fx2Clk_in,
		 web => web13,
		 addrb => addrb13,
		 dinb => dinb13,
		 doutb => doutb13
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------
	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram14 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea14,
		 addra => addra14,
		 dina => dina14,
		 douta => douta14,
		 clkb => fx2Clk_in,
		 web => web14,
		 addrb => addrb14,
		 dinb => dinb14,
		 doutb => doutb14
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram15 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea15,
		 addra => addra15,
		 dina => dina15,
		 douta => douta15,
		 clkb => fx2Clk_in,
		 web => web15,
		 addrb => addrb15,
		 dinb => dinb15,
		 doutb => doutb15
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram16 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea16,
		 addra => addra16,
		 dina => dina16,
		 douta => douta16,
		 clkb => fx2Clk_in,
		 web => web16,
		 addrb => addrb16,
		 dinb => dinb16,
		 doutb => doutb16
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram17 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea17,
		 addra => addra17,
		 dina => dina17,
		 douta => douta17,
		 clkb => fx2Clk_in,
		 web => web17,
		 addrb => addrb17,
		 dinb => dinb17,
		 doutb => doutb17
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram18 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea18,
		 addra => addra18,
		 dina => dina18,
		 douta => douta18,
		 clkb => fx2Clk_in,
		 web => web18,
		 addrb => addrb18,
		 dinb => dinb18,
		 doutb => doutb18
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram19 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea19,
		 addra => addra19,
		 dina => dina19,
		 douta => douta19,
		 clkb => fx2Clk_in,
		 web => web19,
		 addrb => addrb19,
		 dinb => dinb19,
		 doutb => doutb19
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram21 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea21,
		 addra => addra21,
		 dina => dina21,
		 douta => douta21,
		 clkb => fx2Clk_in,
		 web => web21,
		 addrb => addrb21,
		 dinb => dinb21,
		 doutb => doutb21
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram22 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea22,
		 addra => addra22,
		 dina => dina22,
		 douta => douta22,
		 clkb => fx2Clk_in,
		 web => web22,
		 addrb => addrb22,
		 dinb => dinb22,
		 doutb => doutb22
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram23 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea23,
		 addra => addra23,
		 dina => dina23,
		 douta => douta23,
		 clkb => fx2Clk_in,
		 web => web23,
		 addrb => addrb23,
		 dinb => dinb23,
		 doutb => doutb23
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram24 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea24,
		 addra => addra24,
		 dina => dina24,
		 douta => douta24,
		 clkb => fx2Clk_in,
		 web => web24,
		 addrb => addrb24,
		 dinb => dinb24,
		 doutb => doutb24
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram25 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea25,
		 addra => addra25,
		 dina => dina25,
		 douta => douta25,
		 clkb => fx2Clk_in,
		 web => web25,
		 addrb => addrb25,
		 dinb => dinb25,
		 doutb => doutb25
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram26 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea26,
		 addra => addra26,
		 dina => dina26,
		 douta => douta26,
		 clkb => fx2Clk_in,
		 web => web26,
		 addrb => addrb26,
		 dinb => dinb26,
		 doutb => doutb26
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram27 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea27,
		 addra => addra27,
		 dina => dina27,
		 douta => douta27,
		 clkb => fx2Clk_in,
		 web => web27,
		 addrb => addrb27,
		 dinb => dinb27,
		 doutb => doutb27
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram28 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea28,
		 addra => addra28,
		 dina => dina28,
		 douta => douta28,
		 clkb => fx2Clk_in,
		 web => web28,
		 addrb => addrb28,
		 dinb => dinb28,
		 doutb => doutb28
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

	------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
	bram29 : bram
	  PORT MAP (
		 clka => fx2Clk_in,
		 wea => wea29,
		 addra => addra29,
		 dina => dina29,
		 douta => douta29,
		 clkb => fx2Clk_in,
		 web => web29,
		 addrb => addrb29,
		 dinb => dinb29,
		 doutb => doutb29
	  );
	-- INST_TAG_END ------ End INSTANTIATION Template ------------

------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
bram31 : calculated
  PORT MAP (
    clka => fx2Clk_in,
    wea => wea31,
    addra => addra31,
    dina => dina31,
    douta => douta31
  );
-- INST_TAG_END ------ End INSTANTIATION Template ------------

------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
bram32 : calculated
  PORT MAP (
    clka => fx2Clk_in,
    wea => wea32,
    addra => addra32,
    dina => dina32,
    douta => douta32
  );
-- INST_TAG_END ------ End INSTANTIATION Template ------------
------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
bram33 : calculated
  PORT MAP (
    clka => fx2Clk_in,
    wea => wea33,
    addra => addra33,
    dina => dina33,
    douta => douta33
  );
-- INST_TAG_END ------ End INSTANTIATION Template ------------




	-- Assuming for RAM write increment-write-increment order
	process(fx2Clk_in)
	begin
		if ( rising_edge(fx2Clk_in) ) then
	--For color Blue
	
	-----------increment addra when channel 1 write------------------
			if(chanAddr = "0000001" and h2fValid = '1') then
				addra1 <= addra1 + "0000000000001";
			end if;
	-----------increment addrb when channel 1 read-------------------		
			if(chanAddr = "0000001" and f2hReady='1') then
				addrb1 <= addrb1 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb1 <= "0000000000000";
			end if;
	
	-----------increment addra when channel 2 write------------------
			if(chanAddr = "0000010" and h2fValid = '1') then
				addra2 <= addra2 + "0000000000001";
			end if;
	-----------increment addrb when channel 2 read-------------------		
			if(chanAddr = "0000010" and f2hReady='1') then
				addrb2 <= addrb2 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb2 <= "0000000000000";
			end if;
	
	-----------increment addra when channel 3 write------------------
			if(chanAddr = "0000011" and h2fValid = '1') then
				addra3 <= addra3 + "0000000000001";
			end if;
	-----------increment addrb when channel 3 read-------------------		
			if(chanAddr = "0000011" and f2hReady='1') then
				addrb3 <= addrb3 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb3 <= "0000000000000";
			end if;
	
	-----------increment addra when channel 4 write------------------
			if(chanAddr = "0000100" and h2fValid = '1') then
				addra4 <= addra4 + "0000000000001";
			end if;
	-----------increment addrb when channel 4 read-------------------		
			if(chanAddr = "0000100" and f2hReady='1') then
				addrb4 <= addrb4 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb4 <= "0000000000000";
			end if;
	
	-----------increment addra when channel 5 write------------------
			if(chanAddr = "0000101" and h2fValid = '1') then
				addra5 <= addra5 + "0000000000001";
			end if;
	-----------increment addrb when channel 5 read-------------------		
			if(chanAddr = "0000101" and f2hReady='1') then
				addrb5 <= addrb5 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb5 <= "0000000000000";
			end if;
	
	-----------increment addra when channel 6 write------------------
			if(chanAddr = "0000110" and h2fValid = '1') then
				addra6 <= addra6 + "0000000000001";
			end if;
	-----------increment addrb when channel 6 read-------------------		
			if(chanAddr = "0000110" and f2hReady='1') then
				addrb6 <= addrb6 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb6 <= "0000000000000";
			end if;
	
	-----------increment addra when channel 7 write------------------
			if(chanAddr = "0000111" and h2fValid = '1') then
				addra7 <= addra7 + "0000000000001";
			end if;
	-----------increment addrb when channel 7 read-------------------		
			if(chanAddr = "0000111" and f2hReady='1') then
				addrb7 <= addrb7 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb7 <= "0000000000000";
			end if;
	
	-----------increment addra when channel 8 write------------------
			if(chanAddr = "0001000" and h2fValid = '1') then
				addra8 <= addra8 + "0000000000001";
			end if;
	-----------increment addrb when channel 8 read-------------------		
			if(chanAddr = "0001000" and f2hReady='1') then
				addrb8 <= addrb8 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb8 <= "0000000000000";
			end if;
	
	-----------increment addra when channel 9 write------------------
			if(chanAddr = "0001001" and h2fValid = '1') then
				addra9 <= addra9 + "0000000000001";
			end if;
	-----------increment addrb when channel 9 read-------------------		
			if(chanAddr = "0001001" and f2hReady='1') then
				addrb9 <= addrb9 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb9 <= "0000000000000";
			end if;
	
	
	--NOTE:::--CHANNEL NUMBERS ARE IN HEXADECIMAL
	
		
	-----------increment addra when channel 11 write------------------
			if(chanAddr = "0010001" and h2fValid = '1') then
				addra11 <= addra11 + "0000000000001";
			end if;
	-----------increment addrb when channel 1 read-------------------		
			if(chanAddr = "0010001" and f2hReady='1') then
				addrb11 <= addrb11 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb11 <= "0000000000000";
			end if;
	
	-----------increment addra when channel 12 write------------------
			if(chanAddr = "0010010" and h2fValid = '1') then
				addra12 <= addra12 + "0000000000001";
			end if;
	-----------increment addrb when channel 12 read-------------------		
			if(chanAddr = "0010010" and f2hReady='1') then
				addrb12 <= addrb12 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb12 <= "0000000000000";
			end if;
	
	-----------increment addra when channel 13 write------------------
			if(chanAddr = "0010011" and h2fValid = '1') then
				addra13 <= addra13 + "0000000000001";
			end if;
	-----------increment addrb when channel 13 read-------------------		
			if(chanAddr = "0010011" and f2hReady='1') then
				addrb13 <= addrb13 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb13 <= "0000000000000";
			end if;
	
	-----------increment addra when channel 14 write------------------
			if(chanAddr = "0010100" and h2fValid = '1') then
				addra14 <= addra14 + "0000000000001";
			end if;
	-----------increment addrb when channel 14 read-------------------		
			if(chanAddr = "0010100" and f2hReady='1') then
				addrb14 <= addrb14 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb14 <= "0000000000000";
			end if;
	
	-----------increment addra when channel 15 write------------------
			if(chanAddr = "0010101" and h2fValid = '1') then
				addra15 <= addra15 + "0000000000001";
			end if;
	-----------increment addrb when channel 15 read-------------------		
			if(chanAddr = "0010101" and f2hReady='1') then
				addrb15 <= addrb15 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb15 <= "0000000000000";
			end if;
	
	-----------increment addra when channel 16 write------------------
			if(chanAddr = "0010110" and h2fValid = '1') then
				addra16 <= addra16 + "0000000000001";
			end if;
	-----------increment addrb when channel 16 read-------------------		
			if(chanAddr = "0010110" and f2hReady='1') then
				addrb16 <= addrb16 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb16 <= "0000000000000";
			end if;
	
	-----------increment addra when channel 17 write------------------
			if(chanAddr = "0010111" and h2fValid = '1') then
				addra17 <= addra17 + "0000000000001";
			end if;
	-----------increment addrb when channel 17 read-------------------		
			if(chanAddr = "0010111" and f2hReady='1') then
				addrb17 <= addrb17 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb17 <= "0000000000000";
			end if;
	
	-----------increment addra when channel 18 write------------------
			if(chanAddr = "0011000" and h2fValid = '1') then
				addra18 <= addra18 + "0000000000001";
			end if;
	-----------increment addrb when channel 18 read-------------------		
			if(chanAddr = "0011000" and f2hReady='1') then
				addrb18 <= addrb18 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb18 <= "0000000000000";
			end if;
	
	-----------increment addra when channel 19 write------------------
			if(chanAddr = "0011001" and h2fValid = '1') then
				addra19 <= addra19 + "0000000000001";
			end if;
	-----------increment addrb when channel 19 read-------------------		
			if(chanAddr = "0011001" and f2hReady='1') then
				addrb19 <= addrb19 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb19 <= "0000000000000";
			end if;
	
		
	-----------increment addra when channel 21 write------------------
			if(chanAddr = "0100001" and h2fValid = '1') then
				addra21 <= addra21 + "0000000000001";
			end if;
	-----------increment addrb when channel 21 read-------------------		
			if(chanAddr = "0100001" and f2hReady='1') then
				addrb21 <= addrb21 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb21 <= "0000000000000";
			end if;
	
	-----------increment addra when channel 22 write------------------
			if(chanAddr = "0100010" and h2fValid = '1') then
				addra22 <= addra22 + "0000000000001";
			end if;
	-----------increment addrb when channel 22 read-------------------		
			if(chanAddr = "0100010" and f2hReady='1') then
				addrb22 <= addrb22 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb22 <= "0000000000000";
			end if;
	
	-----------increment addra when channel 23 write------------------
			if(chanAddr = "0100011" and h2fValid = '1') then
				addra23 <= addra23 + "0000000000001";
			end if;
	-----------increment addrb when channel 23 read-------------------		
			if(chanAddr = "0100011" and f2hReady='1') then
				addrb23 <= addrb23 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb23 <= "0000000000000";
			end if;
	
	-----------increment addra when channel 24 write------------------
			if(chanAddr = "0100100" and h2fValid = '1') then
				addra24 <= addra24 + "0000000000001";
			end if;
	-----------increment addrb when channel 24 read-------------------		
			if(chanAddr = "0100100" and f2hReady='1') then
				addrb24 <= addrb24 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb24 <= "0000000000000";
			end if;
	
	-----------increment addra when channel 25 write------------------
			if(chanAddr = "0100101" and h2fValid = '1') then
				addra25 <= addra25 + "0000000000001";
			end if;
	-----------increment addrb when channel 25 read-------------------		
			if(chanAddr = "0100101" and f2hReady='1') then
				addrb25 <= addrb25 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb25 <= "0000000000000";
			end if;
	
	-----------increment addra when channel 26 write------------------
			if(chanAddr = "0100110" and h2fValid = '1') then
				addra26 <= addra26 + "0000000000001";
			end if;
	-----------increment addrb when channel 26 read-------------------		
			if(chanAddr = "0100110" and f2hReady='1') then
				addrb26 <= addrb26 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb26 <= "0000000000000";
			end if;
	
	-----------increment addra when channel 27 write------------------
			if(chanAddr = "0100111" and h2fValid = '1') then
				addra27 <= addra27 + "0000000000001";
			end if;
	-----------increment addrb when channel 27 read-------------------		
			if(chanAddr = "0100111" and f2hReady='1') then
				addrb27 <= addrb27 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb27 <= "0000000000000";
			end if;
	
	-----------increment addra when channel 28 write------------------
			if(chanAddr = "0101000" and h2fValid = '1') then
				addra28 <= addra28 + "0000000000001";
			end if;
	-----------increment addrb when channel 28 read-------------------		
			if(chanAddr = "0101000" and f2hReady='1') then
				addrb28 <= addrb28 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb28 <= "0000000000000";
			end if;
	
	-----------increment addra when channel 29 write------------------
			if(chanAddr = "0101001" and h2fValid = '1') then
				addra29 <= addra29 + "0000000000001";
			end if;
	-----------increment addrb when channel 29 read-------------------		
			if(chanAddr = "0101001" and f2hReady='1') then
				addrb29 <= addrb29 + "0000000000001";
			end if;
	-----------reset address of port b when channel 0 active---------
			if(chanAddr = "0000000") then
				addrb29 <= "0000000000000";
			end if;
		end if;
	end process;
	
	--write enable on when channels has data from host
	wea1 <="1" when chanAddr = "0000001" and h2fValid = '1' else "0";
	web1 <="0";
	wea2 <="1" when chanAddr = "0000010" and h2fValid = '1' else "0";
	web2 <="0";
	wea3 <="1" when chanAddr = "0000011" and h2fValid = '1' else "0";
	web3 <="0";
	wea4 <="1" when chanAddr = "0000100" and h2fValid = '1' else "0";
	web4 <="0";
	wea5 <="1" when chanAddr = "0000101" and h2fValid = '1' else "0";
	web5 <="0";
	wea6 <="1" when chanAddr = "0000110" and h2fValid = '1' else "0";
	web6 <="0";
	wea7 <="1" when chanAddr = "0000111" and h2fValid = '1' else "0";
	web7 <="0";
	wea8 <="1" when chanAddr = "0001000" and h2fValid = '1' else "0";
	web8 <="0";
	wea9 <="1" when chanAddr = "0001001" and h2fValid = '1' else "0";
	web9 <="0";
	--write enable on when channels has data from host
	wea11 <="1" when chanAddr = "0010001" and h2fValid = '1' else "0";
	web11 <="0";
	wea12 <="1" when chanAddr = "0010010" and h2fValid = '1' else "0";
	web12 <="0";
	wea13 <="1" when chanAddr = "0010011" and h2fValid = '1' else "0";
	web13 <="0";
	wea14 <="1" when chanAddr = "0010100" and h2fValid = '1' else "0";
	web14 <="0";
	wea15 <="1" when chanAddr = "0010101" and h2fValid = '1' else "0";
	web15 <="0";
	wea16 <="1" when chanAddr = "0010110" and h2fValid = '1' else "0";
	web16 <="0";
	wea17 <="1" when chanAddr = "0010111" and h2fValid = '1' else "0";
	web17 <="0";
	wea18 <="1" when chanAddr = "0011000" and h2fValid = '1' else "0";
	web18 <="0";
	wea19 <="1" when chanAddr = "0011001" and h2fValid = '1' else "0";
	web19 <="0";
	--write enable on when channels has data from host
	wea21 <="1" when chanAddr = "0100001" and h2fValid = '1' else "0";
	web21 <="0";
	wea22 <="1" when chanAddr = "0100010" and h2fValid = '1' else "0";
	web22 <="0";
	wea23 <="1" when chanAddr = "0100011" and h2fValid = '1' else "0";
	web23 <="0";
	wea24 <="1" when chanAddr = "0100100" and h2fValid = '1' else "0";
	web24 <="0";
	wea25 <="1" when chanAddr = "0100101" and h2fValid = '1' else "0";
	web25 <="0";
	wea26 <="1" when chanAddr = "0100110" and h2fValid = '1' else "0";
	web26 <="0";
	wea27 <="1" when chanAddr = "0100111" and h2fValid = '1' else "0";
	web27 <="0";
	wea28 <="1" when chanAddr = "0101000" and h2fValid = '1' else "0";
	web28 <="0";
	wea29 <="1" when chanAddr = "0101001" and h2fValid = '1' else "0";
	web29 <="0";
	wea31 <="0";
	wea32 <="0";
	wea33 <="0";

	-----------------data always sent to din , but written only when en=1
	dina1 <= h2fData when chanAddr = "0000001" and h2fValid = '1' else "00000000";
	--dinb1 <= h2fData;
	dina2 <= h2fData when chanAddr = "0000010" and h2fValid = '1' else "00000000";
	--dinb2 <= h2fData;
	dina3 <= h2fData when chanAddr = "0000011" and h2fValid = '1' else "00000000";
	--dinb3 <= h2fData;
	dina4 <= h2fData when chanAddr = "0000100" and h2fValid = '1' else "00000000";
	--dinb4 <= h2fData;
	dina5 <= h2fData when chanAddr = "0000101" and h2fValid = '1' else "00000000";
	--dinb5 <= h2fData;
	dina6 <= h2fData when chanAddr = "0000110" and h2fValid = '1' else "00000000";
	--dinb6 <= h2fData;
	dina7 <= h2fData when chanAddr = "0000111" and h2fValid = '1' else "00000000";
	--dinb7 <= h2fData;
	dina8 <= h2fData when chanAddr = "0001000" and h2fValid = '1' else "00000000";
	--dinb8 <= h2fData;
	dina9 <= h2fData when chanAddr = "0001001" and h2fValid = '1' else "00000000";
	--dinb9 <= h2fData;
	-------------------data always sent to din , but written only when en=1
	dina11 <= h2fData when chanAddr = "0010001" and h2fValid = '1' else "00000000";
	--dinb11 <= h2fData;
	dina12 <= h2fData when chanAddr = "0010010" and h2fValid = '1' else "00000000";
	--dinb12 <= h2fData;
	dina13 <= h2fData when chanAddr = "0010011" and h2fValid = '1' else "00000000";
	--dinb13 <= h2fData;
	dina14 <= h2fData when chanAddr = "0010100" and h2fValid = '1' else "00000000";
	--dinb14 <= h2fData;
	dina15 <= h2fData when chanAddr = "0010101" and h2fValid = '1' else "00000000";
	--dinb15 <= h2fData;
	dina16 <= h2fData when chanAddr = "0010110" and h2fValid = '1' else "00000000";
	--dinb16 <= h2fData;
	dina17 <= h2fData when chanAddr = "0010111" and h2fValid = '1' else "00000000";
	--dinb17 <= h2fData;
	dina18 <= h2fData when chanAddr = "0011000" and h2fValid = '1' else "00000000";
	--dinb18 <= h2fData;
	dina19 <= h2fData when chanAddr = "0011001" and h2fValid = '1' else "00000000";
	--dinb19 <= h2fData;
	----------------data always sent to din , but written only when en=1
	dina21 <= h2fData when chanAddr = "0100001" and h2fValid = '1' else "00000000";
	--dinb21 <= h2fData;
	dina22 <= h2fData when chanAddr = "0100010" and h2fValid = '1' else "00000000";
	--dinb22 <= h2fData;
	dina23 <= h2fData when chanAddr = "0100011" and h2fValid = '1' else "00000000";
	--dinb23 <= h2fData;
	dina24 <= h2fData when chanAddr = "0100100" and h2fValid = '1' else "00000000";
	--dinb24 <= h2fData;
	dina25 <= h2fData when chanAddr = "0100101" and h2fValid = '1' else "00000000";
	--dinb25 <= h2fData;
	dina26 <= h2fData when chanAddr = "0100110" and h2fValid = '1' else "00000000";
	--dinb26 <= h2fData;
	dina27 <= h2fData when chanAddr = "0100111" and h2fValid = '1' else "00000000";
	--dinb27 <= h2fData;
	dina28 <= h2fData when chanAddr = "0101000" and h2fValid = '1' else "00000000";
	--dinb28 <= h2fData;
	dina29 <= h2fData when chanAddr = "0101001" and h2fValid = '1' else "00000000";
	--dinb29 <= h2fData;
	
	process(chanAddr)
	begin
		if( chanAddr = "0010000") then
			for i in 0 to 255 loop
				for j in 0 to 255 loop
					if((i=0 or i=255) and j mod 3=0) then
						dina31 <= (doutb1);
						addrb1 <= addrb1 + "0000000000001";
						addra31 <=addra31 + "0000000000001";
						dina32 <= (doutb11);
						addrb11 <= addrb11 + "0000000000001";
						addra32 <=addra32 + "0000000000001";
						dina33 <= (doutb21);
						addrb21 <= addrb21 + "0000000000001";
						addra33 <=addra33 + "0000000000001";
					elsif((i=0 or i=255) and j mod 3=1) then
						dina31 <= (doutb4);
						addrb4 <= addrb4 + "0000000000001";
						addra31 <=addra31 + "0000000000001";
						dina32 <= (doutb14);
						addrb14 <= addrb14 + "0000000000001";
						addra32 <=addra32 + "0000000000001";
						dina33 <= (doutb24);
						addrb24 <= addrb24 + "0000000000001";
						addra33 <=addra33 + "0000000000001";
					elsif((i=0 or i=255) and j mod 3=2) then
						dina31 <= (doutb7);
						addrb7 <= addrb7 + "0000000000001";
						addra31 <=addra31 + "0000000000001";
						dina32 <= (doutb17);
						addrb17 <= addrb17 + "0000000000001";
						addra32 <=addra32 + "0000000000001";
						dina33 <= (doutb27);
						addrb27 <= addrb27 + "0000000000001";
						addra33 <=addra33 + "0000000000001";
					elsif((j=0 or j=255) and i mod 3=0) then
						dina31 <= (doutb1);
						addrb1 <= addrb1 + "0000000000001";
						addra31 <=addra31 + "0000000000001";
						dina32 <= (doutb11);
						addrb11 <= addrb11 + "0000000000001";
						addra32 <=addra32 + "0000000000001";
						dina33 <= (doutb21);
						addrb21 <= addrb21 + "0000000000001";
						addra33 <=addra33 + "0000000000001";
					elsif((j=0 or j=255) and i mod 3=1) then
						dina31 <= (doutb2);
						addrb2 <= addrb2 + "0000000000001";
						addra31 <=addra31 + "0000000000001";
						dina32 <= (doutb12);
						addrb12 <= addrb12 + "0000000000001";
						addra32 <=addra32 + "0000000000001";
						dina33 <= (doutb22);
						addrb22 <= addrb22 + "0000000000001";
						addra33 <=addra33 + "0000000000001";
					elsif((j=0 or j=255) and i mod 3=2) then
						dina31 <= (doutb3);
						addrb3 <= addrb3 + "0000000000001";
						addra31 <=addra31 + "0000000000001";
						dina32 <= (doutb13);
						addrb13 <= addrb13 + "0000000000001";
						addra32 <=addra32 + "0000000000001";
						dina33 <= (doutb23);
						addrb23 <= addrb23 + "0000000000001";
						addra33 <=addra33 + "0000000000001";
					elsif(j mod 3=1) then
						dina31<= std_logic_vector(unsigned(doutb1)+unsigned(doutb2)+unsigned(doutb3)+unsigned(doutb4)+unsigned(doutb5)+unsigned(doutb6)+unsigned(doutb7)+unsigned(doutb8)+unsigned(doutb9)/9);
						addrb1 <= addrb1 + "0000000000001";
						addrb2 <= addrb2 + "0000000000001";
						addrb3 <= addrb3 + "0000000000001";
						addra31 <= addra31 + "0000000000001";
					dina32<=std_logic_vector(unsigned(doutb11)+unsigned(doutb12)+unsigned(doutb13)+unsigned(doutb14)+unsigned(doutb15)+unsigned(doutb16)+unsigned(doutb17)+unsigned(doutb18)+unsigned(doutb19)/9);
						addrb11 <= addrb11 + "0000000000001";
						addrb12 <= addrb12 + "0000000000001";
						addrb13 <= addrb13 + "0000000000001";
						addra32 <= addra32 + "0000000000001";
					dina33<=std_logic_vector(unsigned(doutb21)+unsigned(doutb22)+unsigned(doutb23)+unsigned(doutb24)+unsigned(doutb25)+unsigned(doutb26)+unsigned(doutb27)+unsigned(doutb28)+unsigned(doutb29)/9);
						addrb21 <= addrb21 + "0000000000001";
						addrb22 <= addrb22 + "0000000000001";
						addrb23 <= addrb23 + "0000000000001";
						addra33 <= addra33 + "0000000000001";
					elsif(j mod 3=2) then
						dina31<=std_logic_vector(unsigned(doutb1)+unsigned(doutb2)+unsigned(doutb3)+unsigned(doutb4)+unsigned(doutb5)+unsigned(doutb6)+unsigned(doutb7)+unsigned(doutb8)+unsigned(doutb9)/9);
						addrb4 <= addrb4 + "0000000000001";
						addrb5 <= addrb5 + "0000000000001";
						addrb6 <= addrb6 + "0000000000001";
						addra31 <= addra31 + "0000000000001";
					dina32<=std_logic_vector(unsigned(doutb11)+unsigned(doutb12)+unsigned(doutb13)+unsigned(doutb14)+unsigned(doutb15)+unsigned(doutb16)+unsigned(doutb17)+unsigned(doutb18)+unsigned(doutb19)/9);
						addrb14 <= addrb14 + "0000000000001";
						addrb15 <= addrb15 + "0000000000001";
						addrb16 <= addrb16 + "0000000000001";
						addra32 <= addra32 + "0000000000001";
					dina33<=std_logic_vector(unsigned(doutb21)+unsigned(doutb22)+unsigned(doutb23)+unsigned(doutb24)+unsigned(doutb25)+unsigned(doutb26)+unsigned(doutb27)+unsigned(doutb28)+unsigned(doutb29)/9);
						addrb24 <= addrb24 + "0000000000001";
						addrb25 <= addrb25 + "0000000000001";
						addrb26 <= addrb26 + "0000000000001";
						addra33 <= addra33 + "0000000000001";
					elsif(j mod 3=0) then
						dina31<=std_logic_vector(unsigned(doutb1)+unsigned(doutb2)+unsigned(doutb3)+unsigned(doutb4)+unsigned(doutb5)+unsigned(doutb6)+unsigned(doutb7)+unsigned(doutb8)+unsigned(doutb9)/9);
						addrb7 <= addrb7 + "0000000000001";
						addrb8 <= addrb8 + "0000000000001";
						addrb9 <= addrb9 + "0000000000001";
						addra31 <= addra31 + "0000000000001";
					dina32<=std_logic_vector(unsigned(doutb11)+unsigned(doutb12)+unsigned(doutb13)+unsigned(doutb14)+unsigned(doutb15)+unsigned(doutb16)+unsigned(doutb17)+unsigned(doutb18)+unsigned(doutb19)/9);
						addrb17 <= addrb17 + "0000000000001";
						addrb18 <= addrb18 + "0000000000001";
						addrb19 <= addrb19 + "0000000000001";
						addra32 <= addra32 + "0000000000001";
					dina33<=std_logic_vector(unsigned(doutb21)+unsigned(doutb22)+unsigned(doutb23)+unsigned(doutb24)+unsigned(doutb25)+unsigned(doutb26)+unsigned(doutb27)+unsigned(doutb28)+unsigned(doutb29)/9);
						addrb27 <= addrb27 + "0000000000001";
						addrb28 <= addrb28 + "0000000000001";
						addrb29 <= addrb29 + "0000000000001";
						addra33 <= addra33 + "0000000000001";
					end if;
				end loop;
			if(i =0) then
				addrb1 <= addrb1 + "0000000000001";
				addrb11 <= addrb11 + "0000000000001";
				addrb21 <= addrb21 + "0000000000001";
				addrb4 <= addrb4 + "0000000000001";
				addrb14 <= addrb14 + "0000000000001";
				addrb24 <= addrb24 + "0000000000001";
				addrb7 <= addrb7 + "0000000000001";
				addrb17 <= addrb17 + "0000000000001";
				addrb27 <= addrb27 + "0000000000001";
			elsif(i mod 3 = 1) then
				addrb1 <= addrb1 + "0000000000001";
				addrb11 <= addrb11 + "0000000000001";
				addrb21 <= addrb21 + "0000000000001";
				addrb4 <= addrb4 + "0000000000001";
				addrb14 <= addrb14 + "0000000000001";
				addrb24 <= addrb24 + "0000000000001";
				addrb7 <= addrb7 + "0000000000001";
				addrb17 <= addrb17 + "0000000000001";
				addrb27 <= addrb27 + "0000000000001";
				addrb2 <= addrb2 - "0000001010101";
				addrb12 <= addrb12 - "0000001010101";
				addrb22 <= addrb22 - "0000001010101";
				addrb5 <= addrb5 - "0000001010100";
				addrb15 <= addrb15 - "0000001010100";
				addrb25 <= addrb25 - "0000001010100";
				addrb8 <= addrb8 - "0000001010100";
				addrb18 <= addrb18 - "0000001010100";
				addrb28 <= addrb28 - "0000001010100";
				addrb3 <= addrb3 - "0000001010101";
				addrb13 <= addrb13 - "0000001010101";
				addrb23 <= addrb23 - "0000001010101";
				addrb6 <= addrb6 - "0000001010100";
				addrb16 <= addrb16 - "0000001010100";
				addrb26 <= addrb26 - "0000001010100";
				addrb9 <= addrb9 - "0000001010100";
				addrb19 <= addrb19 - "0000001010100";
				addrb29 <= addrb29 - "0000001010100";
			elsif(i mod 3 = 2) then
				addrb2 <= addrb2 + "0000000000001";
				addrb12 <= addrb12 + "0000000000001";
				addrb22 <= addrb22 + "0000000000001";
				addrb5 <= addrb5 + "0000000000001";
				addrb15 <= addrb15 + "0000000000001";
				addrb25 <= addrb25 + "0000000000001";
				addrb8 <= addrb8 + "0000000000001";
				addrb18 <= addrb18 + "0000000000001";
				addrb28 <= addrb28 + "0000000000001";
				addrb1 <= addrb1 - "0000001010101";
				addrb11 <= addrb11 - "0000001010101";
				addrb21 <= addrb21 - "0000001010101";
				addrb4 <= addrb4 - "0000001010100";
				addrb14 <= addrb14 - "0000001010100";
				addrb24 <= addrb24 - "0000001010100";
				addrb7 <= addrb7 - "0000001010100";
				addrb17 <= addrb17 - "0000001010100";
				addrb27 <= addrb27 - "0000001010100";
				addrb3 <= addrb3 - "0000001010101";
				addrb13 <= addrb13 - "0000001010101";
				addrb23 <= addrb23 - "0000001010101";
				addrb6 <= addrb6 - "0000001010100";
				addrb16 <= addrb16 - "0000001010100";
				addrb26 <= addrb26 - "0000001010100";
				addrb9 <= addrb9 - "0000001010100";
				addrb19 <= addrb19 - "0000001010100";
				addrb29 <= addrb29 - "0000001010100";
			elsif(i mod 3 = 0) then
				addrb3 <= addrb3 + "0000000000001";
				addrb13 <= addrb13 + "0000000000001";
				addrb23 <= addrb23 + "0000000000001";
				addrb6 <= addrb6 + "0000000000001";
				addrb16 <= addrb16 + "0000000000001";
				addrb26 <= addrb26 + "0000000000001";
				addrb9 <= addrb9 + "0000000000001";
				addrb19 <= addrb19 + "0000000000001";
				addrb29 <= addrb29 + "0000000000001";
				addrb1 <= addrb1 - "0000001010101";
				addrb11 <= addrb11 - "0000001010101";
				addrb21 <= addrb21 - "0000001010101";
				addrb4 <= addrb4 - "0000001010100";
				addrb14 <= addrb14 - "0000001010100";
				addrb24 <= addrb24 - "0000001010100";
				addrb7 <= addrb7 - "0000001010100";
				addrb17 <= addrb17 - "0000001010100";
				addrb27 <= addrb27 - "0000001010100";
				addrb2 <= addrb2 - "0000001010101";
				addrb12 <= addrb12 - "0000001010101";
				addrb22 <= addrb22 - "0000001010101";
				addrb5 <= addrb5 - "0000001010100";
				addrb15 <= addrb15 - "0000001010100";
				addrb25 <= addrb25 - "0000001010100";
				addrb8 <= addrb8 - "0000001010100";
				addrb18 <= addrb18 - "0000001010100";
				addrb28 <= addrb28 - "0000001010100";
			end if;
			
			end loop;	
		end if;
	end process;	
	-- Select values to return for each channel when the host is reading
	with chanAddr select f2hData <=
		slide_sw_in 	when "0000000", -- return status of slide switches when reading R0
		doutb1				when "0000001",
		doutb2				when "0000010",
		doutb3				when "0000011",
		doutb4				when "0000100",
		doutb5				when "0000101",
		doutb6				when "0000110",
		doutb7				when "0000111",
		doutb8				when "0001000",
		doutb9				when "0001001",
		doutb11				when "0010001",
		doutb12				when "0010010",
		doutb13				when "0010011",
		doutb14				when "0010100",
		doutb15				when "0010101",
		doutb16				when "0010110",
		doutb17				when "0010111",
		doutb18				when "0011000",
		doutb19				when "0011001",
		doutb21				when "0100001",
		doutb22				when "0100010",
		doutb23				when "0100011",
		doutb24				when "0100100",
		doutb25				when "0100101",
		doutb26				when "0100110",
		doutb27				when "0100111",
		doutb28				when "0101000",
		doutb29				when "0101001",
		douta31				when "0110001",
		douta32				when "0110010",
		douta33				when "0110011",
		x"00" 			when others;
---------------------------------------------------------------------------------------------------
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
	led_out <= douta3;
end behavioural;
