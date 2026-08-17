module c3ed::font;
import std, raylib6, c3ed, std::compression::gzip;

const char[] EMBEDDED_FONT_GZ = $embed("../dep/IntoneMonoNerdFontMono-Regular.ttf.gz");

const int FONT_SIZE           = 20;
const int LINE_HEIGHT         = 20;
const int VERTICAL_OFFSET     = -1;

const int GLYPH_WIDTH_CELLS   = 5;
const int GLYPH_HEIGHT_CELLS  = 8;
const int GLYPH_SPACING_CELLS = 1;

char[] cached_decompressed_font = {};

RLFont ttf_font;
bool ttf_loaded = false;

List{RLFont} fallback_fonts;
List{String} cached_fallback_paths;

int current_loaded_size = 0;
int ttf_char_width = 10;

HashSet{int} registered_codepoints;
List{int} active_codepoints;

RLTexture font_texture;
bool font_texture_ready = false;

fn char[] get_embedded_font_bytes() @private
{
	if (cached_decompressed_font.len == 0)
	{
		char[]? decompressed = gzip::uncompress_bytes(mem, EMBEDDED_FONT_GZ);
		if (try bytes = decompressed)
		{
			cached_decompressed_font = bytes;
		}
	}
	return cached_decompressed_font;
}

fn int get_char_width(float scale)
{
	if (ttf_loaded)
	{
		return math::max(1, ttf_char_width);
	}
	return (int)math::round((float)(GLYPH_WIDTH_CELLS + GLYPH_SPACING_CELLS) * scale);
}

fn int get_char_height(float scale)
{
	if (ttf_loaded)
	{
		return math::max(1, current_loaded_size);
	}
	return (int)math::round((float)GLYPH_HEIGHT_CELLS * scale);
}

fn int get_line_height(float scale)
{
	if (ttf_loaded)
	{
		float ratio = (float)current_loaded_size / (float)FONT_SIZE;
		return math::max(1, (int)math::round((float)LINE_HEIGHT * ratio));
	}
	int ch = get_char_height(scale);
	return ch + math::max(4, (int)math::round(6.0f * scale));
}

enum FontGlyph : (Char32 ch, ulong bitmap)
{
	A { 'A', 0b01110_10001_10001_11111_10001_10001_10001_00000UL },
	B { 'B', 0b11110_10001_10001_11110_10001_10001_11110_00000UL },
	C { 'C', 0b01111_10000_10000_10000_10000_10000_01111_00000UL },
	D { 'D', 0b11110_10001_10001_10001_10001_10001_11110_00000UL },
	E { 'E', 0b11111_10000_10000_11110_10000_10000_11111_00000UL },
	F { 'F', 0b11111_10000_10000_11110_10000_10000_10000_00000UL },
	G { 'G', 0b01111_10000_10000_10111_10001_10001_01111_00000UL },
	H { 'H', 0b10001_10001_10001_11111_10001_10001_10001_00000UL },
	I { 'I', 0b01110_00100_00100_00100_00100_00100_01110_00000UL },
	J { 'J', 0b00111_00010_00010_00010_00010_10010_01100_00000UL },
	K { 'K', 0b10001_10010_10100_11000_10100_10010_10001_00000UL },
	L { 'L', 0b10000_10000_10000_10000_10000_10000_11111_00000UL },
	M { 'M', 0b10001_11011_10101_10101_10001_10001_10001_00000UL },
	N { 'N', 0b10001_11001_10101_10011_10001_10001_10001_00000UL },
	O { 'O', 0b01110_10001_10001_10001_10001_10001_01110_00000UL },
	P { 'P', 0b11110_10001_10001_11110_10000_10000_10000_00000UL },
	Q { 'Q', 0b01110_10001_10001_10001_10101_10010_01101_00000UL },
	R { 'R', 0b11110_10001_10001_11110_10100_10010_10001_00000UL },
	S { 'S', 0b01111_10000_10000_01110_00001_00001_11110_00000UL },
	T { 'T', 0b11111_00100_00100_00100_00100_00100_00100_00000UL },
	U { 'U', 0b10001_10001_10001_10001_10001_10001_01110_00000UL },
	V { 'V', 0b10001_10001_10001_10001_10001_01010_00100_00000UL },
	W { 'W', 0b10001_10001_10001_10101_10101_11011_10001_00000UL },
	X { 'X', 0b10001_10001_01010_00100_01010_10001_10001_00000UL },
	Y { 'Y', 0b10001_10001_01010_00100_00100_00100_00100_00000UL },
	Z { 'Z', 0b11111_00001_00010_00100_01000_10000_11111_00000UL },

	LOWER_A { 'a', 0b00000_00000_01111_00001_01111_10001_01111_00000UL },
	LOWER_B { 'b', 0b10000_10000_11110_10001_10001_10001_11110_00000UL },
	LOWER_C { 'c', 0b00000_00000_01111_10000_10000_10000_01111_00000UL },
	LOWER_D { 'd', 0b00001_00001_01111_10001_10001_10001_01111_00000UL },
	LOWER_E { 'e', 0b00000_00000_01111_10001_11111_10000_01111_00000UL },
	LOWER_F { 'f', 0b00110_01001_01000_11110_01000_01000_01000_00000UL },
	LOWER_G { 'g', 0b00000_00000_01111_10001_10001_01111_00001_11110UL },
	LOWER_H { 'h', 0b10000_10000_11110_10001_10001_10001_10001_00000UL },
	LOWER_I { 'i', 0b00100_00000_01100_00100_00100_00100_01110_00000UL },
	LOWER_J { 'j', 0b00010_00000_00010_00010_00010_00010_10010_01100UL },
	LOWER_K { 'k', 0b10000_10000_10010_10100_11000_10100_10010_00000UL },
	LOWER_L { 'l', 0b01100_00100_00100_00100_00100_00100_01110_00000UL },
	LOWER_M { 'm', 0b00000_00000_11010_10101_10101_10101_10101_00000UL },
	LOWER_N { 'n', 0b00000_00000_11110_10001_10001_10001_10001_00000UL },
	LOWER_O { 'o', 0b00000_00000_01110_10001_10001_10001_01110_00000UL },
	LOWER_P { 'p', 0b00000_00000_11110_10001_10001_11110_10000_10000UL },
	LOWER_Q { 'q', 0b00000_00000_01111_10001_10001_01111_00001_00001UL },
	LOWER_R { 'r', 0b00000_00000_10110_11001_10000_10000_10000_00000UL },
	LOWER_S { 's', 0b00000_00000_01111_10000_01110_00001_11110_00000UL },
	LOWER_T { 't', 0b00100_00100_11111_00100_00100_00100_00011_00000UL },
	LOWER_U { 'u', 0b00000_00000_10001_10001_10001_10011_01101_00000UL },
	LOWER_V { 'v', 0b00000_00000_10001_10001_10001_01010_00100_00000UL },
	LOWER_W { 'w', 0b00000_00000_10001_10001_10101_10101_01010_00000UL },
	LOWER_X { 'x', 0b00000_00000_10001_01010_00100_01010_10001_00000UL },
	LOWER_Y { 'y', 0b00000_00000_10001_10001_10001_01111_00001_11110UL },
	LOWER_Z { 'z', 0b00000_00000_11111_00010_00100_01000_11111_00000UL },

	ZERO        { '0', 0b01110_10001_10011_10101_11001_10001_01110_00000UL },
	ONE         { '1', 0b00100_01100_00100_00100_00100_00100_01110_00000UL },
	TWO         { '2', 0b01110_10001_00001_00010_00100_01000_11111_00000UL },
	THREE       { '3', 0b11111_00010_00100_00010_00001_10001_01110_00000UL },
	FOUR        { '4', 0b00010_00110_01010_10010_11111_00010_00010_00000UL },
	FIVE        { '5', 0b11111_10000_11110_00001_00001_10001_01110_00000UL },
	SIX         { '6', 0b00110_01000_10000_11110_10001_10001_01110_00000UL },
	SEVEN       { '7', 0b11111_00001_00010_00100_01000_01000_01000_00000UL },
	EIGHT       { '8', 0b01110_10001_10001_01110_10001_10001_01110_00000UL },
	NINE        { '9', 0b01110_10001_10001_01111_00001_00010_01100_00000UL },
	SPACE       { ' ', 0b00000_00000_00000_00000_00000_00000_00000_00000UL },
	DOT         { '.', 0b00000_00000_00000_00000_00000_00110_00110_00000UL },
	COMMA       { ',', 0b00000_00000_00000_00000_00000_00110_00100_01000UL },
	EXCLAMATION { '!', 0b00100_00100_00100_00100_00100_00000_00100_00000UL },
	QUESTION    { '?', 0b01110_10001_00001_00010_00100_00000_00100_00000UL },
	COLON       { ':', 0b00000_00000_00110_00110_00000_00110_00110_00000UL },
	SEMICOLON   { ';', 0b00000_00000_00110_00110_00000_00110_00100_01000UL },
	QUOTE       { '"', 0b01010_01010_01010_00000_00000_00000_00000_00000UL },
	APOSTROPHE  { '\'', 0b00100_00100_00100_00000_00000_00000_00000_00000UL },
	HYPHEN      { '-', 0b00000_00000_00000_11111_00000_00000_00000_00000UL },
	PLUS        { '+', 0b00000_00100_00100_11111_00100_00100_00000_00000UL },
	EQUALS      { '=', 0b00000_00000_11111_00000_11111_00000_00000_00000UL },
	LESS        { '<', 0b00010_00100_01000_10000_01000_00100_00010_00000UL },
	GREATER     { '>', 0b01000_00100_00010_00001_00010_00100_01000_00000UL },
	LPAREN      { '(', 0b00010_00100_01000_01000_01000_00100_00010_00000UL },
	RPAREN      { ')', 0b01000_00100_00010_00010_00010_00100_01000_00000UL },
	LBRACKET    { '[', 0b01110_01000_01000_01000_01000_01000_01110_00000UL },
	RBRACKET    { ']', 0b01110_00010_00010_00010_00010_00010_01110_00000UL },
	LBRACE      { '{', 0b00011_00100_00100_01000_00100_00100_00011_00000UL },
	RBRACE      { '}', 0b11000_00100_00100_00010_00100_00100_11000_00000UL },
	SLASH       { '/', 0b00001_00010_00010_00100_00100_01000_01000_10000UL },
	BACKSLASH   { '\\', 0b10000_01000_01000_00100_00100_00010_00010_00001UL },
	UNDERSCORE  { '_', 0b00000_00000_00000_00000_00000_00000_00000_11111UL },
	ASTERISK    { '*', 0b00000_01010_00100_11111_00100_01010_00000_00000UL },
	HASH        { '#', 0b01010_01010_11111_01010_11111_01010_01010_00000UL },
	AT          { '@', 0b01110_10001_10111_10101_10110_10000_01111_00000UL },
	AMPERSAND   { '&', 0b01100_10010_01100_01010_10001_10010_01101_00000UL },
	TILDE       { '~', 0b00000_00000_01101_10010_00000_00000_00000_00000UL },
	BACKTICK    { '`', 0b01000_00100_00010_00000_00000_00000_00000_00000UL },
	DOLLAR      { '$', 0b00100_01111_10100_01110_00101_11110_00100_00000UL },
	PERCENT     { '%', 0b11000_11001_00010_00100_01000_10011_00011_00000UL },
	CARET       { '^', 0b00100_01010_10001_00000_00000_00000_00000_00000UL },
	PIPE        { '|', 0b00100_00100_00100_00100_00100_00100_00100_00000UL },
	TAB_ARROW   { 0x2192, 0b00000_00100_00010_11111_00010_00100_00000_00000UL },
	EM_DASH     { '—', 0b10000_00000_00000_11111_00000_00000_00000_10000UL },
	UNKNOWN     { '\0', 0b11111_10001_10101_10101_10101_10001_11111_00000UL }
}

fn ulong get_char_bitmap(Char32 c) => runtime::@enum_lookup(FontGlyph, "ch", c).bitmap ?? FontGlyph.UNKNOWN.bitmap;

fn int get_glyph_atlas_index(Char32 c)
{
	if (c < 128) return (int)c;
	switch (c)
	{
		case 0x2192: return 9;
		case 0x00BB: return 9;
		case '—':    return 128;
		default:
			if (c >= 128 && c < 256) return (int)c;
			FontGlyph? g = runtime::@enum_lookup(FontGlyph, "ch", c);
			if (try g)
			{
				if (g.ch == 0x2192) return 9;
				if (g.ch == '—') return 128;
			}
			return 0;
	}
}

fn bool font_has_glyph(RLFont font, int codepoint)
{
	if (font.glyph_count == 0 || font.glyphs == null) return false;
	int idx = rl::get_glyph_index(font, codepoint);
	if (codepoint == '?') return true;
	return font.glyphs[idx].value == codepoint;
}

fn bool add_codepoint(int cp) @private
{
	if (cp <= 0 || cp > 0x10FFFF) return false;
	if (registered_codepoints.contains(cp)) return false;
	registered_codepoints.add(cp);
	active_codepoints.push(cp);
	return true;
}

fn void init_base_codepoints() @private
{
	if (active_codepoints.entries != null) return;
	active_codepoints.init(mem, 512);
	registered_codepoints.init(mem, 512);

	for (int i = 32; i <= 126; i++) add_codepoint(i);
	for (int i = 160; i <= 255; i++) add_codepoint(i);
	for (int i = 0x0100; i <= 0x017F; i++) add_codepoint(i);
	for (int i = 0x2010; i <= 0x2027; i++) add_codepoint(i);
	add_codepoint(0x2192);
	add_codepoint(0x00BB);
}

fn void load_ttf_at_pixel_size(int pixel_size) @private => @pool()
{
	char[] font_bytes = get_embedded_font_bytes();
	if (font_bytes.len == 0) return;

	init_base_codepoints();

	RLFont new_font = rl::load_font_from_memory(
		".ttf".zstr_tcopy(),
		font_bytes.ptr,
		(int)font_bytes.len,
		pixel_size,
		active_codepoints.entries,
		(int)active_codepoints.len()
	);

	if (new_font.texture.id > 0)
	{
		if (ttf_loaded)
		{
			rl::unload_font(ttf_font);
		}
		ttf_font = new_font;
		ttf_loaded = true;
		ttf_font.texture.set_filter(RLTextureFilter.BILINEAR);
		current_loaded_size = pixel_size;

		RLVector2 sz_m = rl::measure_text_ex(ttf_font, "M", (float)pixel_size, 0.0f);
		ttf_char_width = (sz_m.x > 0.0f) ? (int)math::round(sz_m.x) : math::max(1, pixel_size / 2);
	}

	foreach (&fb : fallback_fonts)
	{
		if (fb.texture.id > 0) rl::unload_font(*fb);
	}
	fallback_fonts.clear();

	foreach (fb_path : cached_fallback_paths)
	{
		RLFont fb_f = rl::load_font_ex(
			fb_path.zstr_tcopy(),
			pixel_size,
			active_codepoints.entries,
			(int)active_codepoints.len()
		);
		if (fb_f.texture.id > 0)
		{
			fb_f.texture.set_filter(RLTextureFilter.BILINEAR);
			fallback_fonts.push(fb_f);
		}
	}
}

fn void ensure_font_scale(float scale)
{
	int target_pixel_size = math::max(8, (int)math::round((float)FONT_SIZE * scale));
	if (target_pixel_size != current_loaded_size)
	{
		load_ttf_at_pixel_size(target_pixel_size);
	}
}

fn String find_script_font_for_codepoint(int cp) @private
{
	String font_name = "";
	switch
	{
		case (cp >= 0x2000 && cp <= 0x2BFF) || (cp >= 0x1F000 && cp <= 0x1FFFF):
			font_name = "NotoSansSymbols2-Regular.ttf";
		case cp >= 0x1200 && cp <= 0x139F:
			font_name = "NotoSansEthiopic-Regular.ttf";
		case cp >= 0x0600 && cp <= 0x06FF:
			font_name = "NotoSansArabic-Regular.ttf";
		case cp >= 0x0590 && cp <= 0x05FF:
			font_name = "NotoSansHebrew-Regular.ttf";
		case cp >= 0x0900 && cp <= 0x097F:
			font_name = "NotoSansDevanagari-Regular.ttf";
		case cp >= 0x0E00 && cp <= 0x0E7F:
			font_name = "NotoSansThai-Regular.ttf";
		case cp >= 0x0980 && cp <= 0x09FF:
			font_name = "NotoSansBengali-Regular.ttf";
		case cp >= 0x0D00 && cp <= 0x0D7F:
			font_name = "NotoSansMalayalam-Regular.ttf";
		case cp >= 0x0B80 && cp <= 0x0BFF:
			font_name = "NotoSansTamil-Regular.ttf";
		case cp >= 0x0C00 && cp <= 0x0C7F:
			font_name = "NotoSansTelugu-Regular.ttf";
		case cp >= 0x1000 && cp <= 0x109F:
			font_name = "NotoSansMyanmar-Regular.ttf";
		case cp >= 0x1780 && cp <= 0x17FF:
			font_name = "NotoSansKhmer-Regular.ttf";
		default:
			break;
	}

	if (font_name.len > 0)
	{
		String[*] candidate_dirs = {
			"/usr/share/fonts/noto",
			"/usr/share/fonts/truetype/noto",
			"/usr/share/fonts/TTF",
			"/usr/share/fonts/opentype/noto"
		};
		foreach (dir : candidate_dirs)
		{
			String path = string::tformat("%s/%s", dir, font_name);
			if (file::exists(path)) return path;
		}
	}
	return "";
}

fn void try_load_ttf() @private => @pool()
{
	if (ttf_loaded) return;

	if (cached_fallback_paths.entries == null) cached_fallback_paths.init(mem, 8);
	if (fallback_fonts.entries == null) fallback_fonts.init(mem, 8);

	String[*] base_fallbacks = {
		"/usr/share/fonts/TTF/DejaVuSans.ttf",
		"/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
		"/usr/share/fonts/noto/NotoSansSymbols2-Regular.ttf",
		"/usr/share/fonts/truetype/noto/NotoSansSymbols2-Regular.ttf",
		"/usr/share/fonts/noto/NotoSansSymbols-Regular.ttf",
		"/usr/share/fonts/truetype/noto/NotoSansSymbols-Regular.ttf",
		"/usr/share/fonts/noto/NotoSans-Regular.ttf",
		"/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf"
	};

	foreach (fb : base_fallbacks)
	{
		if (file::exists(fb))
		{
			bool already_added = false;
			foreach (cached : cached_fallback_paths)
			{
				if (cached == fb) { already_added = true; break; }
			}
			if (!already_added)
			{
				cached_fallback_paths.push(fb.copy(mem));
			}
		}
	}

	load_ttf_at_pixel_size(FONT_SIZE);
}

fn void init_font_texture()
{
	if (font_texture_ready) return;
	font_texture_ready = true;

	try_load_ttf();

	RLImage img = rl::gen_image_color(16 * 8, 16 * 8, { 0, 0, 0, 0 });

	for (int i = 0; i < 256; i++)
	{
		ulong bits = 0;
		switch (i)
		{
			case 9:   bits = FontGlyph.TAB_ARROW.bitmap;
			case 128: bits = FontGlyph.EM_DASH.bitmap;
			default:  bits = get_char_bitmap((Char32)i);
		}

		int gx = (i % 16) * 8;
		int gy = (i / 16) * 8;

		for (int row = 0; row < GLYPH_HEIGHT_CELLS; row++)
		{
			for (int col_idx = 0; col_idx < GLYPH_WIDTH_CELLS; col_idx++)
			{
				int bit_pos = 39 - (row * GLYPH_WIDTH_CELLS + col_idx);
				if (((bits >> bit_pos) & 1) != 0)
				{
					rl::image_draw_pixel(&img, gx + col_idx, gy + row, rl::WHITE);
				}
			}
		}
	}

	font_texture = rl::load_texture_from_image(img);
	font_texture.set_filter(RLTextureFilter.POINT);
	rl::unload_image(img);
}

fn void cleanup_font()
{
	if (ttf_loaded)
	{
		rl::unload_font(ttf_font);
		ttf_loaded = false;
	}
	if (cached_decompressed_font.len > 0)
	{
		mem::free(cached_decompressed_font.ptr);
		cached_decompressed_font = {};
	}
	foreach (&fb : fallback_fonts)
	{
		if (fb.texture.id > 0) rl::unload_font(*fb);
	}
	fallback_fonts.free();
	foreach (p : cached_fallback_paths)
	{
		if (p.len > 0) mem::free(p.ptr);
	}
	cached_fallback_paths.free();
	if (font_texture_ready)
	{
		rl::unload_texture(font_texture);
		font_texture_ready = false;
	}
	registered_codepoints.free();
	active_codepoints.free();
}

fn void draw_char(Char32 c, int px, int py, float scale, Color tint)
{
	if (c == ' ' || c == '\r' || c == '\n') return;
	RLColor rl_tint = gfx::to_rl_color(tint);

	if (ttf_loaded)
	{
		int cp = (int)c;
		if (cp == '\t') cp = 0x00BB;

		if (!registered_codepoints.contains(cp))
		{
			String script_font = find_script_font_for_codepoint(cp);
			if (script_font.len > 0)
			{
				bool already = false;
				foreach (p : cached_fallback_paths)
				{
					if (p == script_font) { already = true; break; }
				}
				if (!already) cached_fallback_paths.push(script_font.copy(mem));
			}

			if (add_codepoint(cp))
			{
				load_ttf_at_pixel_size(current_loaded_size);
			}
		}

		float font_size = (float)current_loaded_size;
		float ratio     = (float)current_loaded_size / (float)FONT_SIZE;
		int draw_y      = py + (int)math::round((float)VERTICAL_OFFSET * ratio);

		if (font_has_glyph(ttf_font, cp))
		{
			rl::draw_text_codepoint(ttf_font, cp, { (float)px, (float)draw_y }, font_size, rl_tint);
			return;
		}

		foreach (&fb_font : fallback_fonts)
		{
			if (font_has_glyph(*fb_font, cp))
			{
				rl::draw_text_codepoint(*fb_font, cp, { (float)px, (float)draw_y }, font_size, rl_tint);
				return;
			}
		}

		rl::draw_text_codepoint(ttf_font, cp, { (float)px, (float)draw_y }, font_size, rl_tint);
		return;
	}

	int idx = get_glyph_atlas_index(c);
	if (idx < 0 || idx >= 256) idx = 0;

	int gx = (idx % 16) * 8;
	int gy = (idx / 16) * 8;

	RLRectangle src = { (float)gx, (float)gy, (float)GLYPH_WIDTH_CELLS, (float)GLYPH_HEIGHT_CELLS };
	RLRectangle dst = { (float)px, (float)py, (float)GLYPH_WIDTH_CELLS * scale, (float)GLYPH_HEIGHT_CELLS * scale };
	rl::draw_texture_pro(font_texture, src, dst, { 0, 0 }, 0.0f, rl_tint);
}

fn void draw_tab_guide(int px, int py, int tab_spaces, int char_width, float scale, Color tint)
{
	for (int i = 0; i < tab_spaces - 1; i++)
	{
		draw_char('-', px + i * char_width, py, scale, tint);
	}
	int arrow_x = px + (tab_spaces - 1) * char_width;
	draw_char(0x2192, arrow_x, py, scale, tint);
}

fn void draw_text(String str, int px, int py, float scale, Color tint)
{
	int advance         = get_char_width(scale);
	int cur_x           = px;
	StringIterator iter = str.iterator();
	while (try Char32 c = iter.next())
	{
		draw_char(c, cur_x, py, scale, tint);
		cur_x += advance;
	}
}