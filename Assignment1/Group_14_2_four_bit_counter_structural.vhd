----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    12:35:36 01/20/2017 
-- Design Name: 
-- Module Name:    four_bit_counter - Behavioral 
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

--
--			 ______			  _______		   _______			 _______
--			|	    |		    |			|		  |		 |		   |		  |
--			|	    |a     ab| 		|bc   cd|		 |de	 ef|	     |fg
--			|      |------->|			|------>|		 |------>|		  |
--			|      |		    |			|		  |		 |			|		  |
--			|______|			 |_______|		  |_______|			|_______|
--						
--

entity four_bit_counter is
port(
	clock: 	in STD_LOGIC;
	clear:	in STD_LOGIC;
	start:	in STD_LOGIC;
	q :		out STD_LOGIC_VECTOR (3 downto 0)
);
end four_bit_counter;

architecture Structural of four_bit_counter is
	
	--signals for internal structure of counter
	signal a,ab,bc,cd,de,ef,fg:STD_LOGIC;								
	
	--signals for slow clock generation
	signal counter : std_logic_vector (23 downto 0);
	signal slow_clk : std_logic :='0';

	COMPONENT jkflipflop
	PORT(
		j : IN std_logic;
		k : IN std_logic;
		clk : IN std_logic;				
		clr : IN std_logic;       
		q : out std_logic;
		qbar : out std_logic
		);
	END COMPONENT;

begin

	--process for generating slow clock from system clock
	process(clock)
	begin
		if(rising_edge(clock)) then
			counter <= counter + 1;
			if(counter=0) then
				slow_clk <= not slow_clk;
			end if;
		end if;
	end process;
--Creating instances of the four flip flop
	Inst_jkflipflop1: jkflipflop PORT MAP(
			j => start ,										
			k => start ,
			clk =>slow_clk ,
			clr =>clear ,
			q => a 
		);
	Inst_jkflipflop2: jkflipflop PORT MAP(
			j => ab,
			k => ab ,
			clk =>slow_clk ,
			clr => clear,
			q => bc 
		);
		
	Inst_jkflipflop3: jkflipflop PORT MAP(
			j => cd,
			k => cd,
			clk =>slow_clk	 ,
			clr =>clear ,
			q => de
		);
		
	Inst_jkflipflop4: jkflipflop PORT MAP(
			j => ef ,
			k => ef,
			clk =>slow_clk ,
			clr => clear,
			q => fg
		);
--updating signals and output
	ab<=a and start;
	cd<=ab and bc;
	ef<=de and cd;
	Q(0)<=ab;
	Q(1)<=bc;
	Q(2)<=de;
	Q(3)<=fg;

end Structural;

