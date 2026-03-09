module top (
    input  wire MCU_CLK,
    
    // SPI Bus (Used to control the test mask)
    input  wire SPI_CS,
    input  wire SPI_SCK,
    input  wire SPI_MOSI,
    output wire SPI_MISO,
    
    // --- TEST PINS TO TOGGLE (Outputs) ---
    // 16 Generic CON Pins
    output wire CON_02, output wire CON_03, output wire CON_04, output wire CON_05,
    output wire CON_06, output wire CON_07, output wire CON_08, output wire CON_09,
    output wire CON_10, output wire CON_11, output wire CON_12, output wire CON_13,
    output wire CON_14, output wire CON_15, output wire CON_16, output wire CON_17,
    
    // 8 EPD Data Pins
    output wire EPD_D0, output wire EPD_D1, output wire EPD_D2, output wire EPD_D3,
    output wire EPD_D4, output wire EPD_D5, output wire EPD_D6, output wire EPD_D7,

    // 7 EPD Control Pins
    output wire EPD_XCL, output wire EPD_LEH, output wire EPD_MODE,
    output wire EPD_CKV, output wire EPD_XSTL, output wire EPD_OE, output wire EPD_STV
);

// --- 1. Async SPI Synchronization ---
reg [2:0] cs_sync;
reg [2:0] sck_sync;
reg [1:0] mosi_sync;

always @(posedge MCU_CLK) begin
    cs_sync   <= {cs_sync[1:0], SPI_CS};
    sck_sync  <= {sck_sync[1:0], SPI_SCK};
    mosi_sync <= {mosi_sync[0], SPI_MOSI};
end

wire cs_active   = ~cs_sync[2]; 
wire sck_falling = (sck_sync[2:1] == 2'b10); 
wire sck_rising  = (sck_sync[2:1] == 2'b01); 
wire mosi_data   = mosi_sync[1];

// --- 2. SPI Mask Decoder & MISO Reply ---
reg [2:0] bit_cnt;
reg [7:0] byte_cnt;
reg [7:0] shift_in;
reg [7:0] shift_out;

reg [7:0] rx_cmd, rx_p0;
reg [31:0] toggle_mask = 0;

always @(posedge MCU_CLK) begin
    if (!cs_active) begin
        bit_cnt   <= 0;
        byte_cnt  <= 0;
        shift_out <= 8'h5A;
    end else begin
        if (sck_rising) begin
            shift_in <= {shift_in[6:0], mosi_data};
            if (bit_cnt == 7) begin
                bit_cnt  <= 0;
                byte_cnt <= byte_cnt + 1;
                
                case (byte_cnt)
                    1: rx_cmd <= {shift_in[6:0], mosi_data};
                    4: rx_p0  <= {shift_in[6:0], mosi_data};
                    5: begin
                        if (rx_cmd == 8'h05) toggle_mask[15:0]  <= {rx_p0, {shift_in[6:0], mosi_data}};
                        if (rx_cmd == 8'h06) toggle_mask[31:16] <= {rx_p0, {shift_in[6:0], mosi_data}};
                    end
                endcase
            end else begin
                bit_cnt <= bit_cnt + 1;
            end
        end
        if (sck_falling) begin
            if (bit_cnt == 0) begin
                if      (byte_cnt == 0) shift_out <= 8'h5A;
                else if (byte_cnt == 1) shift_out <= rx_cmd;
                else                    shift_out <= 8'h00;
            end else begin
                shift_out <= {shift_out[6:0], 1'b0};
            end
        end
    end
end

assign SPI_MISO = cs_active ? shift_out[7] : 1'bz;

// --- 3. Toggle Generator ---
reg toggle_state = 0;
always @(posedge MCU_CLK) toggle_state <= ~toggle_state;

wire toggle_even = toggle_state;
wire toggle_odd  = ~toggle_state;

// =========================================================================
// --- 4. POWER VIRUS: CORE 1.2V MAX LOAD GENERATOR ---
// =========================================================================

// A. Massive Logic Cell (LC) Array - Independent LFSRs (~3200 LCs)
// LFSRs flip pseudo-randomly every cycle (50% toggle rate = max dynamic power).
parameter NUM_LFSR = 75; 
reg [31:0] lfsr [0:NUM_LFSR-1];

integer i;
initial begin
    for (i = 0; i < NUM_LFSR; i = i + 1) begin
        lfsr[i] = 32'h13579BDF ^ (i * 32'h08102040); // Unique starting seeds
    end
end

always @(posedge MCU_CLK) begin
    for (i = 0; i < NUM_LFSR; i = i + 1) begin
        // Standard Galois LFSR polynomial (x^32 + x^22 + x^2 + x^1 + 1)
        lfsr[i] <= {lfsr[i][30:0], 1'b0} ^ (lfsr[i][31] ? 32'h80200003 : 32'h00000000);
    end
end

// B. Block RAM (EBR) Stress (20 of 30 blocks active)
wire [15:0] bram_out_w [0:19];
genvar k;
generate
    for (k = 0; k < 20; k = k + 1) begin : bram_virus
        reg [15:0] ram [0:255];
        reg [7:0] addr = 0;
        reg [15:0] read_data = 0;
        always @(posedge MCU_CLK) begin
            addr <= addr + 8'd7 + k;
            ram[addr] <= ~read_data ^ {16{toggle_state}}; // Thrash the data bits
            read_data <= ram[addr];
        end
        assign bram_out_w[k] = read_data;
    end
endgenerate

// C. SPRAM Stress (All 4 256Kbit RAMs active)
wire [15:0] spram_out_w [0:3];
generate
    for (k = 0; k < 4; k = k + 1) begin : spram_virus
        reg [13:0] s_addr = 0;
        always @(posedge MCU_CLK) s_addr <= s_addr + 14'd123 + k; // Thrash addresses
        
        SB_SPRAM256KA spram_inst (
            .ADDRESS( s_addr ),
            .DATAIN( {16{toggle_state}} ^ s_addr ),
            .MASKWREN( 4'b1111 ),
            .WREN( 1'b1 ),        // Write continuously
            .CHIPSELECT( 1'b1 ),  // Always enabled
            .CLOCK( MCU_CLK ),
            .STANDBY( 1'b0 ),
            .SLEEP( 1'b0 ),
            .POWEROFF( 1'b1 ),
            .DATAOUT( spram_out_w[k] )
        );
    end
endgenerate

// D. Pipelined XOR Reduction Tree 
// Condenses ~3500 flipping bits into 1 wire to stop Yosys from deleting the dead code.
// Pipelining ensures we easily pass the 32MHz timing constraint.
reg [NUM_LFSR-1:0] lfsr_reduce;
reg [19:0] bram_reduce;
reg [3:0]  spram_reduce;

integer j;
always @(posedge MCU_CLK) begin
    for (j = 0; j < NUM_LFSR; j = j + 1) lfsr_reduce[j] <= ^lfsr[j];
    for (j = 0; j < 20;       j = j + 1) bram_reduce[j] <= ^bram_out_w[j];
    for (j = 0; j < 4;        j = j + 1) spram_reduce[j] <= ^spram_out_w[j];
end

wire virus_reduction = (^lfsr_reduce) ^ (^bram_reduce) ^ (^spram_reduce);

// =========================================================================
// --- 5. Apply Masked Output ---
// =========================================================================

assign CON_02 = toggle_mask[0]  ? toggle_even : 1'b0;
assign CON_03 = toggle_mask[1]  ? toggle_odd  : 1'b0;
assign CON_04 = toggle_mask[2]  ? toggle_even : 1'b0;
assign CON_05 = toggle_mask[3]  ? toggle_odd  : 1'b0;
assign CON_06 = toggle_mask[4]  ? toggle_even : 1'b0;
assign CON_07 = toggle_mask[5]  ? toggle_odd  : 1'b0;
assign CON_08 = toggle_mask[6]  ? toggle_even : 1'b0;
assign CON_09 = toggle_mask[7]  ? toggle_odd  : 1'b0;
assign CON_10 = toggle_mask[8]  ? toggle_even : 1'b0;
assign CON_11 = toggle_mask[9]  ? toggle_odd  : 1'b0;
assign CON_12 = toggle_mask[10] ? toggle_even : 1'b0;
assign CON_13 = toggle_mask[11] ? toggle_odd  : 1'b0;
assign CON_14 = toggle_mask[12] ? toggle_even : 1'b0;
assign CON_15 = toggle_mask[13] ? toggle_odd  : 1'b0;
assign CON_16 = toggle_mask[14] ? toggle_even : 1'b0;
assign CON_17 = toggle_mask[15] ? toggle_odd  : 1'b0;

// NOTE: We hide the power virus output here on EPD_D0 when not toggling!
assign EPD_D0 = toggle_mask[16] ? toggle_even : virus_reduction; 

assign EPD_D1 = toggle_mask[17] ? toggle_odd  : 1'b0;
assign EPD_D2 = toggle_mask[18] ? toggle_even : 1'b0;
assign EPD_D3 = toggle_mask[19] ? toggle_odd  : 1'b0;
assign EPD_D4 = toggle_mask[20] ? toggle_even : 1'b0;
assign EPD_D5 = toggle_mask[21] ? toggle_odd  : 1'b0;
assign EPD_D6 = toggle_mask[22] ? toggle_even : 1'b0;
assign EPD_D7 = toggle_mask[23] ? toggle_odd  : 1'b0;

assign EPD_XCL  = toggle_mask[24] ? toggle_even : 1'b0;
assign EPD_LEH  = toggle_mask[25] ? toggle_odd  : 1'b0;
assign EPD_MODE = toggle_mask[26] ? toggle_even : 1'b0;
assign EPD_CKV  = toggle_mask[27] ? toggle_odd  : 1'b0;
assign EPD_XSTL = toggle_mask[28] ? toggle_even : 1'b0;
assign EPD_OE   = toggle_mask[29] ? toggle_odd  : 1'b0;
assign EPD_STV  = toggle_mask[30] ? toggle_even : 1'b0;

endmodule