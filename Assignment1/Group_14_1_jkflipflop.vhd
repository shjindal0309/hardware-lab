----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    15:57:18 01/10/2017 
-- Design Name: 
-- Module Name:    jkflipflop - Behavioral 
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

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity jkflipflop is
    Port ( J : in  STD_LOGIC;
           K : in  STD_LOGIC;
           CLK : in  STD_LOGIC;
           clr : in  STD_LOGIC;
           Q : out  STD_LOGIC;
           QBAR : out  STD_LOGIC);
end jkflipflop;

architecture Behavioral of jkflipflop is		--positive-edge triggered
begin

process(clr,CLK)
variable qvar :STD_LOGIC := '0';			--qvar is used to stand for Q (which is an out port and cannot be read directly)
begin
if(clr = '1') then
qvar := '0';
elsif(rising_edge(CLK)) then
	if(J='0' and K='1') then		--reset
	qvar := '0'; 
	end if;

	if(J='1' and K='0') then 		--set
	qvar := '1';
	end if;

	if(J='1' and K='1') then 		--toggle
	qvar := not qvar;
	end if;
end if;
--Finally updating the outputs according to qvar
Q <= qvar;
QBAR <= not qvar;

--by default(if no rising edge of clock and also when J=0,K=0) the flip flop will hold

end process;
end Behavioral;

