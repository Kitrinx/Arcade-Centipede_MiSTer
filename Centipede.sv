//============================================================================
//  Arcade: Centipede
//
//  Port to MiST
//  Copyright (C) 2018 Gehstock
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [44:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,
	
	output CLK_VIDEO_HDMI,
	output CE_PIXEL_HDMI,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] VIDEO_ARX,
	output  [7:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	
	//Split the HDMI out for rotated core
	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_DE,    // = ~(VBlank | HBlank)
	output        HDMI_F1,
	output [1:0]  HDMI_SL,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S, // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)
	input         TAPE_IN,

	// SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,
	output [1:0]  BUFFERMODE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR
);

assign {UART_RTS, UART_TXD, UART_DTR} = 0;

assign AUDIO_S   = 0;
assign AUDIO_MIX = 0;

assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

assign VIDEO_ARX = status[8] ? 8'd16 : status[5] ? 8'd3 : 8'd4;
assign VIDEO_ARY = status[8] ? 8'd9  : status[5] ? 8'd4 : 8'd3;

assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CKE, SDRAM_CLK, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;


////////////////////////////  HPS I/O  //////////////////////////////////


`include "build_id.v"
parameter CONF_STR = {
	"A.CENTIPEDE;;",
	"-;",
	"O8,Aspect ratio,4:3,16:9,3:4;",
	"O9B,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"OGH,Buffering,Triple,Single,Low Latency;",
	"O5,Rotation,Horizontal,Vertical;",
	"-;",
	"O7,Swap Joysticks,No,Yes;",
	"-;",
	"R0,Reset;",
	"J1,Fire, Coin, Start;",
	"V,v",`BUILD_DATE
};

wire  [1:0] buttons;
wire [31:0] status;
wire        forced_scandoubler;

wire        ioctl_download;
wire [24:0] ioctl_addr;
wire [15:0] ioctl_dout;
wire        ioctl_wait;
wire        ioctl_wr;

wire [15:0] joystick_0,joystick_1;
wire [24:0] ps2_mouse;

wire [2:0] scale = status[11:9];
wire [2:0] sl = scale ? scale - 1'd1 : 3'd0;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_12),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),

	.forced_scandoubler(forced_scandoubler),
	
	.buttons(buttons),
	.status(status),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1)
);

assign BUFFERMODE = (status[17:16] == 2'b00) ? 2'b01 : (status[17:16] == 2'b01) ? 2'b00 : 2'b10;

wire       joy_swap = status[7];

wire [15:0] joya = joy_swap ? joystick_1 : joystick_0;
wire [15:0] joyb = joy_swap ? joystick_0 : joystick_1;




// localparam CONF_STR = {
// 	"Centipede;;",
// 	"O1,Test,off,on;", 
// 	"O34,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
// 	"O5,Joystick Control,Upright,Normal;",	
// 	"T7,Reset;",
// 	"V,v1.00.",`BUILD_DATE
// };


wire clk_24;
wire clk_12;
wire clk_6;
wire clk_100mhz;
wire clock_locked;

pll pll
(	
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_24),
	.outclk_1(clk_12),
	.outclk_2(clk_6),
	.outclk_3(clk_100mhz),
	.locked(clock_locked)
);

wire m_up_1     = ~joya[3];
wire m_down_1   = ~joya[2];
wire m_left_1  =  ~joya[1];
wire m_right_1  = ~joya[0];

wire m_up_2     = ~joyb[3];
wire m_down_2   = ~joyb[2];
wire m_left_2   = ~joyb[1];
wire m_right_2  = ~joyb[0];

wire m_fire1  = ~joyb[4];
wire m_fire2  = ~joya[4];
wire m_start2 = ~joyb[6];
wire m_start1 = ~joya[6];

wire l_coin = ~joyb[5];
wire c_coin = ~joya[5] & ~joyb[5];
wire r_coin = ~joya[5];
wire m_test = ~status[1];
wire m_slam = 1'b1;//generate Noise
wire m_cocktail = 1'b1;

wire 	[9:0] playerinput_i = { r_coin, c_coin, l_coin, m_test, m_cocktail, m_slam, m_start2, m_start1, m_fire1, m_fire2 };
//wire 	[9:0] playerinput_i = { m_coin, coin_c, coin_l, m_test, m_cocktail, m_slam, m_start, start2, fire2, m_fire };

centipede centipede(
	.clk_100mhz(clk_100mhz),
	.clk_12mhz(clk_12),
 	.reset(status[0] | buttons[1]),
	.playerinput_i(playerinput_i),
	.trakball_i(),
	.joystick_i({m_right_1 , m_left_1, m_down_1, m_up_1, m_right_2 , m_left_2, m_down_2, m_up_2}),
	.sw1_i(8'h54),
	.sw2_i(8'b0),
	.rgb_o({b, g, r}),
	.hsync_o(hs),
	.vsync_o(vs),
	.hblank_o(hblank),
	.vblank_o(vblank),
	.audio_o(audio)
	);


wire [3:0] audio;

assign AUDIO_L = {audio, audio, audio, audio};

assign AUDIO_R = AUDIO_L;

wire hs, vs;
wire [2:0] b, g, r;
wire hblank, vblank;
wire blankn = ~(hblank | vblank);


assign CLK_VIDEO = clk_12;
assign VGA_SL = sl[1:0];
assign VGA_F1 = 0;

wire ce_pix = clk_6;

assign VGA_R = {r, r, r[2:1]};
assign VGA_G = {g, g, g[2:1]};
assign VGA_B = {b, b, b[2:1]};

assign VGA_HS = hs;
assign VGA_VS = vs;
assign VGA_DE = ~hblank;
assign CE_PIXEL = clk_6;

assign HDMI_R = status[5] ? {rr, rr, rr[2:1]} : VGA_R;
assign HDMI_B = status[5] ? {rg, rg, rg[2:1]} : VGA_G;
assign HDMI_G = status[5] ? {rb, rb, rb[2:1]} : VGA_B;

assign HDMI_HS = status[5] ? rhs : VGA_HS;
assign HDMI_VS = status[5] ? rvs : VGA_VS;
assign HDMI_DE = status[5] ? rde : VGA_DE;

assign CE_PIXEL_HDMI = status[5] ? 1'd1 : CE_PIXEL;
assign CLK_VIDEO_HDMI = status[5] ? clk_24 : CLK_VIDEO;

wire [2:0] rr;
wire [2:0] rg;
wire [2:0] rb;
wire rhs;
wire rvs;
wire rde;

screen_rotate #(.WIDTH(256), .HEIGHT(224), .DEPTH(9), .MARGIN(8), .CCW(1)) screen_rotate
(
	.clk_in(clk_12),
	.ce_in(clk_6),
	.video_in({b, g, r}),
	.hblank(hblank),
	.vblank(vblank),
	.clk_out(clk_24),
	.video_out({rb, rg, rr}),
	.hsync(rhs),
	.vsync(rvs),
	.de(rde)
);

// wire [7:0] mr;
// wire [7:0] mg;
// wire [7:0] mb;
// wire mhs;
// wire mvs;
// wire mde;
// wire mce_pixel;

// video_mixer #(.LINE_LENGTH(480), .HALF_DEPTH(0)) video_mixer
// (	
// 	.clk_sys(CLK_VIDEO),
// 	.ce_pix(CE_PIXEL),
// 	.R(VGA_R),
// 	.G(VGA_G),
// 	.B(VGA_B),
// 	.HSync(VGA_HS),
// 	.VSync(VGA_VS),
// 	.scandoubler(0),
// 	.HBlank(hblank),
// 	.VBlank(vblank),
// 	.hq2x(0),
// 	.scanlines(0),
// 	.ce_pix_out(mce_pixel),
// 	.mono(0),
// 	.VGA_R(mr),
// 	.VGA_G(mg),
// 	.VGA_B(mb),
// 	.VGA_VS(mvs),
// 	.VGA_HS(mhs),
// 	.VGA_DE(mde)
// );

// video_mixer #(.LINE_LENGTH(480), .HALF_DEPTH(1)) video_mixer
// (
// 	.clk_sys(clk_24),
// 	.ce_pix(clk_6),
// 	.ce_pix_actual(clk_6),
// 	.SPI_SCK(SPI_SCK),
// 	.SPI_SS3(SPI_SS3),
// 	.SPI_DI(SPI_DI),
// 	.R(blankn?{r,r}:"000000"),
// 	.G(blankn?{g,g}:"000000"),
// 	.B(blankn?{b,b}:"000000"),
// 	.HSync(hs),
// 	.VSync(vs),
// 	.VGA_R(VGA_R),
// 	.VGA_G(VGA_G),
// 	.VGA_B(VGA_B),
// 	.VGA_VS(VGA_VS),
// 	.VGA_HS(VGA_HS),
// 	.scandoubler_disable(scandoubler_disable),
// 	.scanlines(scandoubler_disable ? 2'b00 : {status[4:3] == 2'b11, status[4:3] == 2'b10, status[4:3] == 2'b01}),
// 	.hq2x(status[4:3]==1),
// 	.ypbpr_full(1),
// 	.line_start(0),
// 	.mono(0)
// );



endmodule
