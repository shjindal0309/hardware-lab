----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    19:36:09 01/18/2017 
-- Design Name: 
-- Module Name:    four-bit-counter-fsm - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
--
-- Dependencies: 
--
-- Revision: 
-- Revision 0.01 - File Created
-- Additional Comments: 
--
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;				--needed for arithmetic and relation operations for vectors	

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity four_bit_counter_fsm is
    Port ( reset : 			in  STD_LOGIC;
           clk : 	 			in  STD_LOGIC;
           count_enable :  in  STD_LOGIC;
           Q : 				out  STD_LOGIC_VECTOR (3 downto 0));
end four_bit_counter_fsm;

architecture Behavioral of four_bit_counter_fsm is
	--signals for slow clock generation
	signal counter : std_logic_vector (23 downto 0);
	signal slow_clk : std_logic :='0';
begin

	--process for generating slow clock(so that can view the counter functioning) from system clock
	process(clk)
	begin
		if(rising_edge(clk)) then
			counter <= counter + 1;
			if(counter=0) then
				slow_clk <= not slow_clk;
			end if;
		end if;
	end process;

	--4-bit-counter process
	process(reset,slow_clk)
		variable qvar : STD_LOGIC_VECTOR (3 downto 0) := "0000";				--since Q is out port so to know current state(Q) using a variable 
	begin
		if(reset='1') then																--reset(asynchronuous) the counter to the state 0000
			qvar := "0000";
			Q <= qvar;
		elsif(rising_edge(slow_clk)) then											--coding like incrementation(behavior of up counter)
			if(count_enable = '1') then
				qvar := qvar+1;	
				Q <= qvar;
			end if;
		end if;
	end process;

end Behavioral;

