library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.constants.all;

entity dcache is
	port (	clk : in std_logic;
			address : in std_logic_vector (ADDRESS_WIDTH-1 downto 0);  --from CPU
			data_out : out std_logic_vector (DATA_WIDTH-1 downto 0) := (others => 'Z');   --to CPU
			data_in : in std_logic_vector (DATA_WIDTH-1 downto 0);	   -- from CPU
			mem_address : out std_logic_vector (ADDRESS_WIDTH-1 downto 0) := (others => 'Z'); --to mem
			bus_in : in std_logic_vector (DATA_WIDTH-1 downto 0); 		--from mem
			bus_out : out std_logic_vector (DATA_WIDTH-1 downto 0) := (others => 'Z');		--to mem
			rw_cache : in std_logic; 		--1: read, 0: write
			i_d_cache : in std_logic; 		--1: Instruction, 0: Data
			cache_enable : in std_logic;
			data_cache_ready : out std_logic := 'Z';
			mem_enable : out std_logic := 'Z';
			mem_rw : out std_logic := 'Z';
			mem_data_ready : in std_logic;
			DHc : out std_logic;
			IHc : out std_logic);
end dcache;

architecture behavioral of dcache is
	signal dcache : dcachearray;
	signal dtag : std_logic_vector(DCACHE_TAG_SIZE-1 downto 0);
	signal dindex : std_logic_vector(DCACHE_INDEX_SIZE-1 downto 0);
	signal dword_offset : std_logic_vector(DCACHE_WORD_OFFSET-1 downto 0);

	signal icache : icachearray := (others => ('0', (others => '0'), (others => (others => '0'))));
	signal itag : std_logic_vector(ICACHE_TAG_SIZE-1 downto 0);
	signal iindex : std_logic_vector(ICACHE_INDEX_SIZE-1 downto 0);
	signal iword_offset : std_logic_vector(ICACHE_WORD_OFFSET-1 downto 0);

begin
	process
		variable selected_set : integer;
		variable present_block : integer;
		variable present : boolean := false;
		variable selected_word_offset : integer;
		variable selected_block : integer;
	begin
	wait until cache_enable='1';
	data_out <= (others => 'Z');
	data_cache_ready <= 'Z';
	if (i_d_cache = '1') and (rw_cache = '1') then  --inst cache
		data_cache_ready <= '0';
		itag <= address(31 downto 9);
		iindex <= address(8 downto 4);
		iword_offset <= address(3 downto 2);

		wait until clk='1'; --cache access 1 cycle

		selected_block := to_integer(unsigned(iindex));
		selected_word_offset := to_integer(unsigned(iword_offset));

		if (icache(selected_block).tag /= itag) or (icache(selected_block).valid = '0') then --not present
			--bring block from memory
			IHc <= '0';
			for i in 0 to CACHE_BLOCK_SIZE-1 loop --read four 4 words and save to cache
				mem_address <= std_logic_vector(unsigned(std_logic_vector'(address(31 downto 4) & "0000")) + i*4);
				mem_enable <= '1';
				mem_rw <= '1';
				wait until mem_data_ready = '1';
				icache(selected_block).blockdata(i) <= bus_in;
				mem_address <= (others => 'Z');
				mem_enable <= 'Z';
				mem_rw <= 'Z';
			end loop ;
			icache(selected_block).valid <= '1';
		else
			IHc <= '1';
		end if ;

		data_out <= icache(selected_block).blockdata(selected_word_offset);
		wait until clk='1';
		data_cache_ready <= '1';

	elsif (i_d_cache = '0') then  --data cache
		data_cache_ready <= '0';
		dtag <= address(31 downto 7);
		dindex <= address(6 downto 4);
		dword_offset <= address(3 downto 2);

		wait until clk='1'; --cache access 1 cycle

		selected_set := to_integer(unsigned(dindex));
		selected_word_offset := to_integer(unsigned(dword_offset));

		if (dcache(selected_set).blocks(0).tag = dtag) and (dcache(selected_set).blocks(0).valid = '1') then
			present_block := 0;
			present := true;
			DHc <= '1';
		elsif (dcache(selected_set).blocks(1).tag = dtag) and (dcache(selected_set).blocks(1).valid = '1') then
		 	present_block := 1;
		 	present := true;
		 	DHc <= '1';
		else
			present := false;
			DHc <= '0';
		end if ;

		if rw_cache = '0' then  --write
			--write to memory
			mem_address <= address;
			mem_enable <= '1';
			mem_rw <= '0';
			bus_out <= data_in;
			wait for period*11;	--memory port access + write time memory
			mem_address <= (others => 'Z');
			mem_enable <= 'Z';
			mem_rw <= 'Z';
		end if ;

		if present = false then --bring from memory
			present_block := to_integer(not dcache(selected_set).lastused); --selected block --> LRU
			for i in 0 to CACHE_BLOCK_SIZE-1 loop --read four 4 words and save to cache
				mem_address <= std_logic_vector(unsigned(std_logic_vector'(address(31 downto 4) & "0000")) + i*4);
				mem_enable <= '1';
				mem_rw <= '1';
				wait until mem_data_ready = '1';
				dcache(selected_set).blocks(present_block).blockdata(i) <= bus_in;
				mem_address <= (others => 'Z');
				mem_enable <= 'Z';
				mem_rw <= 'Z';
			end loop ;
			dcache(selected_set).blocks(present_block).valid <= '1';
		end if ;

		if rw_cache = '1' then --read
			data_out <= dcache(selected_set).blocks(present_block).blockdata(selected_word_offset);
		elsif (rw_cache = '0') and (present = true) then -- write and hit, then write to cache
			dcache(selected_set).blocks(present_block).blockdata(selected_word_offset) <= data_in;
		end if ;

		dcache(selected_set).lastused <= std_logic(to_unsigned(present_block, 1)(0));
		wait until clk='1';
		data_cache_ready <= '1';

	end if ;

	end process;


end behavioral;