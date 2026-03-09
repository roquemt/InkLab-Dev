# Project Files
TOP_V = zero.v
PCF_FILE = pins.pcf

# Intermediate Files
JSON = hardware.json
ASC = hardware.asc
BIN = hardware.bin

# Tools
YOSYS = yosys
NEXTPNR = nextpnr-ice40
ICEPACK = icepack

# Default Target
all: $(BIN)

# Step 3: Pack ASC into BIN
$(BIN): $(ASC)
	$(ICEPACK) -s $(ASC) $(BIN)

# Step 2: Place and Route (JSON -> ASC)
$(ASC): $(JSON) $(PCF_FILE)
	$(NEXTPNR) --up5k --package sg48 --pcf $(PCF_FILE) --json $(JSON) --asc $(ASC) --freq 12

# Step 1: Synthesis (Verilog -> JSON)
$(JSON): $(TOP_V)
	$(YOSYS) -p "synth_ice40 -top top -json $(JSON)" $(TOP_V)

# Clean up generated files
clean:
	@del /f $(JSON) $(ASC) $(BIN)  2>nul || rm -f $(JSON) $(ASC) $(BIN) 
	@echo Cleaned up intermediate files.

.PHONY: all clean