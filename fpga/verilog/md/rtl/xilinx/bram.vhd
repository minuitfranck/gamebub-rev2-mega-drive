--------------------------------------------------------------
-- Game Bub port of the MiSTer Genesis core: Xilinx-portable
-- replacement for rtl/bram.vhd (kept beside it as bram.vhd.altera),
-- which instantiates altsyncram BIDIR_DUAL_PORT with
-- NEW_DATA_NO_NBE_READ on both ports and unregistered outputs.
--
-- tdp_ram_bank is the PC Engine port's (fpga/verilog/pce/rtl/xilinx/
-- dpram.vhd), itself from the SNES port's bram.vhd: same-port
-- read-during-write returns the new data through a bypass register,
-- as altsyncram does; mixed-port collisions read the OLD data
-- (Xilinx READ_FIRST), which is the safe choice because Altera's
-- M10K leaves that case unspecified and Xilinx WRITE_FIRST would
-- return garbage.
--
-- Entity names, generics, port names and defaults are the upstream
-- ones, so no core file changes: dpram, dpram_dif, DualPortRAM and
-- obj_cache. spram/spram_sz and mlab are not instantiated anywhere in
-- the vendored subset and are not provided.
--
-- mem_init_file is accepted for interface compatibility and asserted
-- against: nothing in this subset initialises a memory from a file
-- (the FX68K microcode ROMs come in through rtl/generated/
-- fx68k_roms.svh instead).
--
-- ASYMMETRIC SHAPE. The core instantiates exactly one memory with
-- different widths on its two ports: the cartridge save RAM,
-- dpram_dif #(17,8,16,16) in system.sv -- port A is the 68000's
-- byte-wide view and port B is the 16-bit host/SD-card view. That is
-- built here from an even-byte and an odd-byte bank so the byte order
-- is explicit and provable:
--
--     port A byte n  <->  port B word n/2, bits 7:0 for even n
--                                          bits 15:8 for odd n
--
-- which is altsyncram's mixed-width convention (the lower narrow
-- address is the least significant part of the wide word). It is what
-- makes our .sav byte-for-byte a MiSTer .sav.
--------------------------------------------------------------

--------------------------------------------------------------
-- One true dual port RAM bank, same width on both ports.
--------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

entity tdp_ram_bank is
	generic (
		addr_width : integer := 8;
		data_width : integer := 8
	);
	port (
		clk0  : in  std_logic;
		en0   : in  std_logic;
		we0   : in  std_logic;
		addr0 : in  unsigned(addr_width-1 downto 0);
		di0   : in  std_logic_vector(data_width-1 downto 0);
		do0   : out std_logic_vector(data_width-1 downto 0);
		clk1  : in  std_logic;
		en1   : in  std_logic;
		we1   : in  std_logic;
		addr1 : in  unsigned(addr_width-1 downto 0);
		di1   : in  std_logic_vector(data_width-1 downto 0);
		do1   : out std_logic_vector(data_width-1 downto 0)
	);
end entity;

architecture SYN of tdp_ram_bank is
	type ram_t is array (0 to 2**addr_width-1) of std_logic_vector(data_width-1 downto 0);
	shared variable ram : ram_t := (others => (others => '0'));
	signal rd0, rd1 : std_logic_vector(data_width-1 downto 0) := (others => '0');
	signal wr0, wr1 : std_logic_vector(data_width-1 downto 0) := (others => '0');
	signal bypass0, bypass1 : std_logic := '0';
begin
	port0 : process(clk0)
	begin
		if rising_edge(clk0) then
			if en0 = '1' then
				rd0 <= ram(to_integer(addr0));
				if we0 = '1' then
					ram(to_integer(addr0)) := di0;
				end if;
				wr0 <= di0;
				bypass0 <= we0;
			end if;
		end if;
	end process;
	do0 <= wr0 when bypass0 = '1' else rd0;

	port1 : process(clk1)
	begin
		if rising_edge(clk1) then
			if en1 = '1' then
				rd1 <= ram(to_integer(addr1));
				if we1 = '1' then
					ram(to_integer(addr1)) := di1;
				end if;
				wr1 <= di1;
				bypass1 <= we1;
			end if;
		end if;
	end process;
	do1 <= wr1 when bypass1 = '1' else rd1;
end SYN;

--------------------------------------------------------------
-- Dual port Block RAM, different parameters on the two ports.
-- Supported shapes: equal widths, and 8 bits on A with 16 on B.
--------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

entity dpram_dif is
	generic (
		addr_width_a  : integer := 8;
		data_width_a  : integer := 8;
		addr_width_b  : integer := 8;
		data_width_b  : integer := 8;
		mem_init_file : string := " "
	);
	PORT
	(
		clock			: in  STD_LOGIC;

		address_a	: in  STD_LOGIC_VECTOR (addr_width_a-1 DOWNTO 0);
		data_a		: in  STD_LOGIC_VECTOR (data_width_a-1 DOWNTO 0) := (others => '0');
		enable_a		: in  STD_LOGIC := '1';
		wren_a		: in  STD_LOGIC := '0';
		q_a			: out STD_LOGIC_VECTOR (data_width_a-1 DOWNTO 0);
		cs_a        : in  std_logic := '1';

		address_b	: in  STD_LOGIC_VECTOR (addr_width_b-1 DOWNTO 0) := (others => '0');
		data_b		: in  STD_LOGIC_VECTOR (data_width_b-1 DOWNTO 0) := (others => '0');
		enable_b		: in  STD_LOGIC := '1';
		wren_b		: in  STD_LOGIC := '0';
		q_b			: out STD_LOGIC_VECTOR (data_width_b-1 DOWNTO 0);
		cs_b        : in  std_logic := '1'
	);
end entity;

ARCHITECTURE SYN OF dpram_dif IS
	signal q0 : std_logic_vector(data_width_a-1 downto 0);
	signal q1 : std_logic_vector(data_width_b-1 downto 0);
	signal we_a, we_b : std_logic;
BEGIN
	assert mem_init_file = " "
		report "dpram_dif: mem_init_file is not supported in the Xilinx port"
		severity failure;
	assert (data_width_a = data_width_b and addr_width_a = addr_width_b)
		or (data_width_a = 8 and data_width_b = 16 and addr_width_a = addr_width_b + 1)
		report "dpram_dif: unsupported port shape in the Xilinx port"
		severity failure;

	q_a <= q0 when cs_a = '1' else (others => '1');
	q_b <= q1 when cs_b = '1' else (others => '1');
	we_a <= wren_a and cs_a;
	we_b <= wren_b and cs_b;

	-- Symmetric: one bank.
	symmetric : if data_width_a = data_width_b generate
		bank : entity work.tdp_ram_bank generic map(addr_width_a, data_width_a)
		port map(
			clk0 => clock, en0 => enable_a, we0 => we_a, addr0 => unsigned(address_a), di0 => data_a, do0 => q0,
			clk1 => clock, en1 => enable_b, we1 => we_b, addr1 => unsigned(address_b), di1 => data_b, do1 => q1
		);
	end generate;

	-- 8 bits on A, 16 on B: an even-byte and an odd-byte bank. Port A
	-- addresses a byte and picks its bank with the low address bit;
	-- port B addresses a pair and sees the even byte in bits 7:0.
	asym_8_16 : if data_width_a /= data_width_b generate
		signal even_q_a, odd_q_a : std_logic_vector(7 downto 0);
		signal even_q_b, odd_q_b : std_logic_vector(7 downto 0);
		signal index_a : unsigned(addr_width_b-1 downto 0);
		signal index_b : unsigned(addr_width_b-1 downto 0);
		signal odd_sel, odd_sel_q : std_logic;
		signal we_even, we_odd : std_logic;
		signal di_even, di_odd : std_logic_vector(7 downto 0);
	begin
		index_a <= unsigned(address_a(addr_width_a-1 downto 1));
		index_b <= unsigned(address_b);
		odd_sel <= address_a(0);
		we_even <= we_a and not odd_sel;
		we_odd  <= we_a and odd_sel;
		di_even <= data_b(7 downto 0);
		di_odd  <= data_b(15 downto 8);

		-- The bank the A port read came from, delayed to match the
		-- memory's one-cycle read (and held while the port is disabled,
		-- as an altsyncram output register is).
		process(clock)
		begin
			if rising_edge(clock) then
				if enable_a = '1' then
					odd_sel_q <= odd_sel;
				end if;
			end if;
		end process;
		q0 <= odd_q_a when odd_sel_q = '1' else even_q_a;
		q1 <= odd_q_b & even_q_b;

		even_bank : entity work.tdp_ram_bank generic map(addr_width_b, 8)
		port map(
			clk0 => clock, en0 => enable_a, we0 => we_even,
			addr0 => index_a, di0 => data_a, do0 => even_q_a,
			clk1 => clock, en1 => enable_b, we1 => we_b,
			addr1 => index_b, di1 => di_even, do1 => even_q_b
		);

		odd_bank : entity work.tdp_ram_bank generic map(addr_width_b, 8)
		port map(
			clk0 => clock, en0 => enable_a, we0 => we_odd,
			addr0 => index_a, di0 => data_a, do0 => odd_q_a,
			clk1 => clock, en1 => enable_b, we1 => we_b,
			addr1 => index_b, di1 => di_odd, do1 => odd_q_b
		);
	end generate;
END SYN;

--------------------------------------------------------------
-- Dual port Block RAM, same parameters on both ports.
--------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;

entity dpram is
	generic (
		addr_width    : integer := 8;
		data_width    : integer := 8;
		mem_init_file : string := " "
	);
	PORT
	(
		clock			: in  STD_LOGIC;

		address_a	: in  STD_LOGIC_VECTOR (addr_width-1 DOWNTO 0);
		data_a		: in  STD_LOGIC_VECTOR (data_width-1 DOWNTO 0) := (others => '0');
		enable_a		: in  STD_LOGIC := '1';
		wren_a		: in  STD_LOGIC := '0';
		q_a			: out STD_LOGIC_VECTOR (data_width-1 DOWNTO 0);
		cs_a        : in  std_logic := '1';

		address_b	: in  STD_LOGIC_VECTOR (addr_width-1 DOWNTO 0) := (others => '0');
		data_b		: in  STD_LOGIC_VECTOR (data_width-1 DOWNTO 0) := (others => '0');
		enable_b		: in  STD_LOGIC := '1';
		wren_b		: in  STD_LOGIC := '0';
		q_b			: out STD_LOGIC_VECTOR (data_width-1 DOWNTO 0);
		cs_b        : in  std_logic := '1'
	);
end entity;

ARCHITECTURE SYN OF dpram IS
BEGIN
	ram : entity work.dpram_dif generic map(addr_width,data_width,addr_width,data_width,mem_init_file)
	port map(clock,address_a,data_a,enable_a,wren_a,q_a,cs_a,address_b,data_b,enable_b,wren_b,q_b,cs_b);
END SYN;

--------------------------------------------------------------
-- Dual port Block RAM same parameters on both ports (for VDP).
--------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;

entity DualPortRAM is
	generic (
		addrbits    : integer := 8;
		databits    : integer := 8
	);
	PORT
	(
		clock			: in  STD_LOGIC;

		address_a	: in  STD_LOGIC_VECTOR (addrbits-1 DOWNTO 0);
		data_a		: in  STD_LOGIC_VECTOR (databits-1 DOWNTO 0) := (others => '0');
		wren_a		: in  STD_LOGIC := '0';
		q_a			: out STD_LOGIC_VECTOR (databits-1 DOWNTO 0);

		address_b	: in  STD_LOGIC_VECTOR (addrbits-1 DOWNTO 0) := (others => '0');
		data_b		: in  STD_LOGIC_VECTOR (databits-1 DOWNTO 0) := (others => '0');
		wren_b		: in  STD_LOGIC := '0';
		q_b			: out STD_LOGIC_VECTOR (databits-1 DOWNTO 0)
	);
end entity;

ARCHITECTURE SYN OF DualPortRAM IS
BEGIN
	ram : entity work.dpram_dif generic map(addrbits,databits,addrbits,databits)
	port map(clock,address_a,data_a,'1',wren_a,q_a,'1',address_b,data_b,'1',wren_b,q_b,'1');
END SYN;

--------------------------------------------------------------
-- Dual port Block RAM with byte enable (VDP sprite cache).
--------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;

ENTITY obj_cache IS
	PORT
	(
		byteena_a	: IN STD_LOGIC_VECTOR (3 DOWNTO 0) :=  (OTHERS => '1');
		clock		: IN STD_LOGIC  := '1';
		data		: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
		rdaddress	: IN STD_LOGIC_VECTOR (6 DOWNTO 0);
		wraddress	: IN STD_LOGIC_VECTOR (6 DOWNTO 0);
		wren		: IN STD_LOGIC  := '0';
		q			: OUT STD_LOGIC_VECTOR (31 DOWNTO 0)
	);
END obj_cache;

ARCHITECTURE SYN OF obj_cache IS
	signal lane_we : std_logic_vector(3 downto 0);
BEGIN
	lanes_we : for i in 0 to 3 generate
		lane_we(i) <= wren and byteena_a(i);
	end generate;
	lanes : for i in 0 to 3 generate
		ram : entity work.dpram_dif generic map(7,8,7,8)
		port map
		(
			clock,
			rdaddress, (others => '0'), '1', '0', q(8*i+7 downto 8*i), '1',
			wraddress, data(8*i+7 downto 8*i), '1', lane_we(i), open, '1'
		);
	end generate;
END SYN;
