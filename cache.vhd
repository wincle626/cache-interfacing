library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.constants.all;

entity cache is
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
			DHc : out std_logic := '0';
			IHc : out std_logic := '0');
end cache;

architecture behavioral of cache is
	signal cache : dcachearray;
	signal tag : std_logic_vector(DCACHE_TAG_SIZE-1 downto 0);
	signal index : std_logic_vector(DCACHE_INDEX_SIZE-1 downto 0);
	signal word_offset : std_logic_vector(DCACHE_WORD_OFFSET-1 downto 0);

	signal icache : icachearray := (others => ('0', (others => '0'), (others => (others => '0'))));
	signal itag : std_logic_vector(ICACHE_TAG_SIZE-1 downto 0);
	signal iindex : std_logic_vector(ICACHE_INDEX_SIZE-1 downto 0);
	signal iword_offset : std_logic_vector(ICACHE_WORD_OFFSET-1 downto 0);
	signal DHc_sig : std_logic := '0';
	signal IHc_sig : std_logic := '0';

begin
	UPDATE_IHIT_FLAG: process --Update external flags so they are 1 only during 1 cycle
	begin
		wait until IHc_sig = '1';
		IHc <= '1';
		wait until clk='1';
		IHc <= '0';
	end process;

	UPDATE_DHIT_FLAG: process
	begin
		wait until DHc_sig = '1';
		DHc <= '1';
		wait until clk='1';
		DHc <= '0';
	end process;

	CACHE_PROC: process
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
		IHc_sig <= '0';

		wait until clk='1';--cache access 1 cycle

		selected_block := to_integer(unsigned(iindex)); --index is the selected block
		selected_word_offset := to_integer(unsigned(iword_offset));

		if (icache(selected_block).tag /= itag) or (icache(selected_block).valid = '0') then --this is a miss
			--bring block from memory
			IHc_sig <= '0';
			for i in 0 to CACHE_BLOCK_SIZE-1 loop --read four 4 words and save to cache
				mem_address <= std_logic_vector(unsigned(std_logic_vector'(address(31 downto 4) & "0000")) + i*4);
				mem_enable <= '1';
				mem_rw <= '1';
				wait until mem_data_ready = '1';
				wait until clk='1';
				icache(selected_block).blockdata(i) <= bus_in;
				mem_address <= (others => 'Z');
				mem_enable <= '0';
				mem_rw <= 'Z';
				wait until mem_data_ready = '0';
			end loop ;
			icache(selected_block).valid <= '1';
			icache(selected_block).tag <= itag;
		else
			IHc_sig <= '1'; --it's a hit
		end if ;

		data_out <= icache(selected_block).blockdata(selected_word_offset);
		data_cache_ready <= '1'; -- data is ready, inform CPU

	elsif (i_d_cache = '0') then  --data cache
		data_cache_ready <= '0';
		tag <= address(31 downto 7);
		index <= address(6 downto 4);
		word_offset <= address(3 downto 2);
		DHc_sig <= '0';

		wait until clk='1'; --cache access 1 cycle

		selected_set := to_integer(unsigned(index));
		selected_word_offset := to_integer(unsigned(word_offset));

		if (cache(selected_set).blocks(0).tag = tag) and (cache(selected_set).blocks(0).valid = '1') then --hit on the first block of selected set
			present_block := 0;
			present := true;
			DHc_sig <= '1';
		elsif (cache(selected_set).blocks(1).tag = tag) and (cache(selected_set).blocks(1).valid = '1') then --hit on the second block of selected set
		 	present_block := 1;
		 	present := true;
		 	DHc_sig <= '1';
		else 				--it's a miss
			present := false;
			DHc_sig <= '0';
		end if ;

		if rw_cache = '0' then  --write always to memory since it's write thru
			--write to memory
			mem_address <= address;
			mem_enable <= '1';
			mem_rw <= '0';
			bus_out <= data_in;
			wait until mem_data_ready = '1'; --wait until memory finishes writing
			mem_address <= (others => 'Z');
			mem_enable <= '0';
			mem_rw <= 'Z';
			if present = false then
				wait until clk='1'; --if it's a miss, wait one cycle before reading so memory is ready
			end if ;
		end if ;

		if present = false then --bring from memory
			present_block := to_integer(not cache(selected_set).lastused); --selected block --> LRU
			for i in 0 to CACHE_BLOCK_SIZE-1 loop --read four 4 words and save to cache
				mem_address <= std_logic_vector(unsigned(std_logic_vector'(address(31 downto 4) & "0000")) + i*4);
				mem_enable <= '1';
				mem_rw <= '1';
				wait until mem_data_ready = '1';
				wait until clk='1';
				cache(selected_set).blocks(present_block).blockdata(i) <= bus_in;
				mem_address <= (others => 'Z');
				mem_enable <= '0';
				mem_rw <= 'Z';
				wait until mem_data_ready = '0';
			end loop ;
			cache(selected_set).blocks(present_block).valid <= '1';
			cache(selected_set).blocks(present_block).tag <= tag;
		end if ;

		if rw_cache = '1' then --if we are reading, output data to CPU
			data_out <= cache(selected_set).blocks(present_block).blockdata(selected_word_offset);
		elsif (rw_cache = '0') and (present = true) then -- if we are writing and it's hit, then write to cache
			cache(selected_set).blocks(present_block).blockdata(selected_word_offset) <= data_in;
		end if ;

		cache(selected_set).lastused <= std_logic(to_unsigned(present_block, 1)(0));
		data_cache_ready <= '1'; --cache is done, inform CPU

	end if ;

	end process;


end behavioral;