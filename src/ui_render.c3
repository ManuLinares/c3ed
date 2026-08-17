module c3ed::ui;
import std, c3ed;

struct TextInputWidget
{
	char[256] buffer;
	int length;
	int cursor_pos;
	int scroll_col;
}

fn int prev_utf8_char_idx(char* buf, int pos) @inline @private
{
	if (pos <= 0) return 0;
	int prev = pos - 1;
	while (prev > 0 && (buf[prev] & 0xC0) == 0x80) prev--;
	return prev;
}

fn int next_utf8_char_idx(char* buf, int pos, int max_len) @inline @private
{
	if (pos >= max_len) return max_len;
	int next = pos + 1;
	while (next < max_len && (buf[next] & 0xC0) == 0x80) next++;
	return next;
}

fn void TextInputWidget.clear(&self)
{
	self.length = 0;
	self.cursor_pos = 0;
	self.scroll_col = 0;
	self.buffer[0] = '\0';
}

fn void TextInputWidget.set_text(&self, String str)
{
	self.clear();
	sz copy_len = math::min(str.len, (sz)254);
	if (copy_len > 0)
	{
		self.buffer[:copy_len] = str[:copy_len];
	}
	self.length = (int)copy_len;
	self.cursor_pos = self.length;
	self.scroll_col = 0;
	self.buffer[self.length] = '\0';
}

fn String TextInputWidget.view(&self) => (String)self.buffer[:self.length];

fn void TextInputWidget.ensure_cursor_visible(&self, int max_visible_cols)
{
	int cursor_col = (int)conv::utf8_codepoints(self.view()[:self.cursor_pos]);
	if (cursor_col < self.scroll_col)
	{
		self.scroll_col = cursor_col;
	}
	if (cursor_col >= self.scroll_col + max_visible_cols)
	{
		self.scroll_col = cursor_col - max_visible_cols + 1;
	}
	if (self.scroll_col < 0) self.scroll_col = 0;
}

fn bool TextInputWidget.insert_codepoint(&self, Char32 cp)
{
	char[4] buf;
	sz len = conv::char32_to_utf8(cp, &buf) ?? 0;
	if (len == 0 || self.length + (int)len >= 255) return false;

	int ins_len = (int)len;
	int remaining = self.length - self.cursor_pos;
	if (remaining > 0)
	{
		mem::move(&self.buffer[self.cursor_pos + ins_len], &self.buffer[self.cursor_pos], (sz)remaining);
	}
	self.buffer[self.cursor_pos:len] = buf[:len];
	self.length += ins_len;
	self.cursor_pos += ins_len;
	self.buffer[self.length] = '\0';
	return true;
}

fn bool TextInputWidget.insert_str(&self, String str)
{
	if (str.len == 0) return false;
	sz available = (sz)math::max(0, 254 - self.length);
	sz to_copy = math::min(str.len, available);
	if (to_copy == 0) return false;

	int ins_len = (int)to_copy;
	int remaining = self.length - self.cursor_pos;
	if (remaining > 0)
	{
		mem::move(&self.buffer[self.cursor_pos + ins_len], &self.buffer[self.cursor_pos], (sz)remaining);
	}
	self.buffer[self.cursor_pos:to_copy] = str[:to_copy];
	self.length += ins_len;
	self.cursor_pos += ins_len;
	self.buffer[self.length] = '\0';
	return true;
}

fn bool TextInputWidget.backspace(&self)
{
	if (self.cursor_pos <= 0) return false;

	int prev = prev_utf8_char_idx(&self.buffer, self.cursor_pos);
	int del_len = self.cursor_pos - prev;
	int remaining = self.length - self.cursor_pos;

	if (remaining > 0)
	{
		mem::move(&self.buffer[prev], &self.buffer[self.cursor_pos], (sz)remaining);
	}
	self.length -= del_len;
	self.cursor_pos = prev;
	self.buffer[self.length] = '\0';
	return true;
}

fn bool TextInputWidget.delete_word_left(&self)
{
	if (self.cursor_pos <= 0) return false;

	int p = prev_utf8_char_idx(&self.buffer, self.cursor_pos);

	while (p > 0)
	{
		int prev = prev_utf8_char_idx(&self.buffer, p);
		char c = self.buffer[prev];
		if (c == ' ' || c == '\t' || c == '/' || c == '\\' || c == '-' || c == '_' || c == '.' || c == ':')
		{
			p = prev;
		}
		else
		{
			break;
		}
	}

	while (p > 0)
	{
		int prev = prev_utf8_char_idx(&self.buffer, p);
		char c = self.buffer[prev];
		if (c.is_alnum() || (c & 0x80) != 0)
		{
			p = prev;
		}
		else
		{
			break;
		}
	}

	if (p == self.cursor_pos && p > 0)
	{
		p = prev_utf8_char_idx(&self.buffer, p);
	}

	int del_len = self.cursor_pos - p;
	if (del_len <= 0) return false;

	int remaining = self.length - self.cursor_pos;
	if (remaining > 0)
	{
		mem::move(&self.buffer[p], &self.buffer[self.cursor_pos], (sz)remaining);
	}
	self.length -= del_len;
	self.cursor_pos = p;
	self.buffer[self.length] = '\0';
	return true;
}

fn bool TextInputWidget.delete(&self)
{
	if (self.cursor_pos >= self.length) return false;

	int next = next_utf8_char_idx(&self.buffer, self.cursor_pos, self.length);
	int del_len = next - self.cursor_pos;
	int remaining = self.length - next;

	if (remaining > 0)
	{
		mem::move(&self.buffer[self.cursor_pos], &self.buffer[next], (sz)remaining);
	}
	self.length -= del_len;
	self.buffer[self.length] = '\0';
	return true;
}

struct ListPickerWidget<ItemType>
{
	List{ItemType} items;
	int selected_index;
	int scroll_offset;
	int visible_rows;
}

fn void ListPickerWidget.init(&self, Allocator allocator, int visible_rows = 10)
{
	self.items.init(allocator, 32);
	self.selected_index = 0;
	self.scroll_offset = 0;
	self.visible_rows = visible_rows;
}

fn void ListPickerWidget.ensure_visible(&self)
{
	int total = (int)self.items.len();
	if (total == 0)
	{
		self.selected_index = 0;
		self.scroll_offset = 0;
		return;
	}
	self.selected_index = math::clamp(self.selected_index, 0, total - 1);
	if (self.selected_index < self.scroll_offset)
	{
		self.scroll_offset = self.selected_index;
	}
	if (self.selected_index >= self.scroll_offset + self.visible_rows)
	{
		self.scroll_offset = self.selected_index - self.visible_rows + 1;
	}
	int max_offset = math::max(0, total - self.visible_rows);
	self.scroll_offset = math::clamp(self.scroll_offset, 0, max_offset);
}

fn void ListPickerWidget.select_next(&self)
{
	int total = (int)self.items.len();
	if (total == 0) return;
	if (self.selected_index + 1 < total)
	{
		self.selected_index++;
	}
	else
	{
		self.selected_index = 0;
		self.scroll_offset = 0;
	}
	self.ensure_visible();
}

fn void ListPickerWidget.select_prev(&self)
{
	int total = (int)self.items.len();
	if (total == 0) return;
	if (self.selected_index > 0)
	{
		self.selected_index--;
	}
	else
	{
		self.selected_index = total - 1;
	}
	self.ensure_visible();
}

fn void ListPickerWidget.page_up(&self)
{
	int total = (int)self.items.len();
	if (total == 0) return;
	int step = math::max(1, self.visible_rows);
	self.selected_index = math::max(0, self.selected_index - step);
	self.scroll_offset = math::max(0, self.scroll_offset - step);
	self.ensure_visible();
}

fn void ListPickerWidget.page_down(&self)
{
	int total = (int)self.items.len();
	if (total == 0) return;
	int step = math::max(1, self.visible_rows);
	self.selected_index = math::min(total - 1, self.selected_index + step);
	self.scroll_offset = math::min(math::max(0, total - self.visible_rows), self.scroll_offset + step);
	self.ensure_visible();
}

fn void ListPickerWidget.clamp_view(&self, int visible_rows)
{
	self.visible_rows = math::max(1, visible_rows);
	self.ensure_visible();
}

struct LayoutMetrics
{
	float font_scale;
	int char_width;
	int char_height;
	int line_height;

	int screen_w;
	int screen_h;

	int tab_bar_height;
	int footer_height;
	int terminal_height;
	int gutter_width;
	int text_start_x;
	int text_start_y;

	int editor_w;
	int editor_h;
	int visible_lines;
	int visible_cols;

	int minimap_w;
	int minimap_x;

	Rect tab_bar_rect;
	Rect gutter_rect;
	Rect editor_rect;
	Rect footer_rect;
	Rect scrollbar_rect;
	Rect minimap_rect;
	Rect terminal_rect;
}

fn int get_digits_count(int n) @private
{
	if (n <= 0) return 1;
	int count = 0;
	while (n > 0)
	{
		count++;
		n /= 10;
	}
	return count;
}

fn LayoutMetrics compute_layout(
	int screen_w,
	int screen_h,
	float font_scale,
	int total_lines,
	bool show_tab_bar = true,
	bool terminal_open = false,
	int terminal_h = config::LAYOUT_METRICS.terminal_default_h
)
{
	LayoutMetrics lm;
	lm.font_scale = math::clamp(font_scale, config::LAYOUT_METRICS.min_font_scale, config::LAYOUT_METRICS.max_font_scale);
	font::ensure_font_scale(lm.font_scale);

	lm.char_width = font::get_char_width(lm.font_scale);
	lm.char_height = font::get_char_height(lm.font_scale);
	lm.line_height = font::get_line_height(lm.font_scale);

	lm.screen_w = screen_w;
	lm.screen_h = screen_h;

	int tab_bar_padding_y = math::max(4, (int)math::round(6.0f * lm.font_scale));
	int footer_padding_y  = math::max(4, (int)math::round(5.0f * lm.font_scale));
	lm.tab_bar_height = show_tab_bar ? (lm.char_height + tab_bar_padding_y * 2) : 0;
	lm.footer_height = lm.char_height + footer_padding_y * 2;
	lm.terminal_height = terminal_open ? math::clamp(terminal_h, config::LAYOUT_METRICS.terminal_min_h, screen_h / 2) : 0;

	int digits = math::max(config::LAYOUT_METRICS.gutter_min_digits, get_digits_count(total_lines));
	lm.gutter_width = digits * lm.char_width + config::LAYOUT_METRICS.gutter_padding_right + config::LAYOUT_METRICS.gutter_border_w + config::LAYOUT_METRICS.gutter_base_margin;
	lm.text_start_x = lm.gutter_width + config::LAYOUT_METRICS.text_padding_x;
	lm.text_start_y = lm.tab_bar_height + config::LAYOUT_METRICS.text_padding_y;

	lm.minimap_w = config::settings.show_minimap ? config::settings.minimap_width : 0;
	lm.minimap_x = screen_w - lm.minimap_w - config::LAYOUT_METRICS.minimap_margin_right;

	lm.editor_w = screen_w - lm.text_start_x - lm.minimap_w - 18;
	lm.editor_h = screen_h - lm.tab_bar_height - lm.footer_height - lm.terminal_height;

	lm.visible_lines = math::max(1, (lm.editor_h - config::LAYOUT_METRICS.text_padding_y * 2) / lm.line_height);
	lm.visible_cols = math::max(1, (lm.editor_w - config::LAYOUT_METRICS.text_padding_x) / lm.char_width);

	lm.tab_bar_rect   = { 0, 0, (float)screen_w, (float)lm.tab_bar_height };
	lm.gutter_rect    = { 0, (float)lm.tab_bar_height, (float)(lm.gutter_width - config::LAYOUT_METRICS.gutter_border_w), (float)lm.editor_h };
	lm.editor_rect    = { (float)lm.text_start_x, (float)lm.text_start_y, (float)lm.editor_w, (float)(lm.editor_h - config::LAYOUT_METRICS.text_padding_y * 2) };
	lm.scrollbar_rect = { (float)(screen_w - config::LAYOUT_METRICS.scrollbar_w - 2), (float)lm.tab_bar_height, (float)config::LAYOUT_METRICS.scrollbar_w, (float)lm.editor_h };
	lm.minimap_rect   = { (float)lm.minimap_x, (float)lm.tab_bar_height, (float)lm.minimap_w, (float)lm.editor_h };
	lm.terminal_rect  = { 0, (float)(screen_h - lm.footer_height - lm.terminal_height), (float)screen_w, (float)lm.terminal_height };
	lm.footer_rect    = { 0, (float)(screen_h - lm.footer_height), (float)screen_w, (float)lm.footer_height };

	return lm;
}

fn void render_modal(Editor* ed, int screen_w, int height, LayoutMetrics* lm)
{
	String prompt   = ed.get_modal_prompt();
	Rect mrect      = ed.get_modal_rect(lm, screen_w, height);
	int modal_x     = (int)mrect.x;
	int modal_y     = (int)mrect.y;
	int modal_w     = (int)mrect.width;
	int modal_h     = (int)mrect.height;
	int input_box_h = math::max(config::LAYOUT_METRICS.modal_input_box_h_min, lm.char_height + config::LAYOUT_METRICS.modal_input_box_padding);

	gfx::draw_rect(modal_x - 4, modal_y - 4, modal_w + 8, modal_h + 8, config::theme.gutter_border);
	gfx::draw_rect(modal_x, modal_y, modal_w, modal_h, config::theme.header_bg);

	int prompt_y = modal_y + config::LAYOUT_METRICS.modal_padding_y;

	if (ed.modal.kind == FIND || ed.modal.kind == REPLACE)
	{
		Rect toggle_rect = ed.get_case_toggle_rect(lm, screen_w, height);
		Vec2 mouse_v = gfx::get_mouse_pos();
		bool is_hover = mouse_v.x >= toggle_rect.x && mouse_v.x <= toggle_rect.x + toggle_rect.width
			&& mouse_v.y >= toggle_rect.y && mouse_v.y <= toggle_rect.y + toggle_rect.height;

		if (is_hover)
		{
			gfx::draw_rect((int)toggle_rect.x, (int)toggle_rect.y, (int)toggle_rect.width, (int)toggle_rect.height, config::theme.selection_bg);
			gfx::draw_rect_lines((int)toggle_rect.x, (int)toggle_rect.y, (int)toggle_rect.width, (int)toggle_rect.height, config::theme.accent_blue);
		}
	}

	font::draw_text(prompt, modal_x + config::LAYOUT_METRICS.modal_padding_x, prompt_y, lm.font_scale, config::theme.accent_blue);

	if (ed.modal.kind == CONFIRM_EXIT || ed.modal.kind == CONFIRM_CLOSE_TAB || ed.modal.kind == CONFIRM_DISK_RELOAD)
	{
		Vec2 mouse_v = gfx::get_mouse_pos();

		int btn_w = (modal_w - 32 - 24) / 3;
		int btn_h = input_box_h;
		int btn_y = modal_y + 14 + lm.char_height + 12;

		int btn1_x = modal_x + 16;
		int btn2_x = btn1_x + btn_w + 12;
		int btn3_x = btn2_x + btn_w + 12;

		bool hover1 = mouse_v.x >= (float)btn1_x && mouse_v.x < (float)(btn1_x + btn_w) && mouse_v.y >= (float)btn_y && mouse_v.y < (float)(btn_y + btn_h);
		bool hover2 = mouse_v.x >= (float)btn2_x && mouse_v.x < (float)(btn2_x + btn_w) && mouse_v.y >= (float)btn_y && mouse_v.y < (float)(btn_y + btn_h);
		bool hover3 = mouse_v.x >= (float)btn3_x && mouse_v.x < (float)(btn3_x + btn_w) && mouse_v.y >= (float)btn_y && mouse_v.y < (float)(btn_y + btn_h);

		gfx::draw_rect(btn1_x, btn_y, btn_w, btn_h, hover1 ? config::theme.accent_green : config::theme.bg);
		gfx::draw_rect_lines(btn1_x, btn_y, btn_w, btn_h, config::theme.accent_green);
		String b1_str = "[Y] Yes";
		font::draw_text(b1_str, btn1_x + (btn_w - (int)b1_str.len * lm.char_width) / 2, btn_y + (btn_h - lm.char_height) / 2, lm.font_scale, hover1 ? config::theme.bg : config::theme.accent_green);

		gfx::draw_rect(btn2_x, btn_y, btn_w, btn_h, hover2 ? config::theme.accent_red : config::theme.bg);
		gfx::draw_rect_lines(btn2_x, btn_y, btn_w, btn_h, hover2 ? config::theme.accent_red : config::theme.gutter_border);
		String b2_str = "[N] No";
		font::draw_text(b2_str, btn2_x + (btn_w - (int)b2_str.len * lm.char_width) / 2, btn_y + (btn_h - lm.char_height) / 2, lm.font_scale, hover2 ? config::theme.bg : config::theme.accent_red);

		gfx::draw_rect(btn3_x, btn_y, btn_w, btn_h, hover3 ? config::theme.selection_bg : config::theme.bg);
		gfx::draw_rect_lines(btn3_x, btn_y, btn_w, btn_h, hover3 ? config::theme.accent_blue : config::theme.gutter_border);
		String b3_str = "[Esc] Cancel";
		font::draw_text(b3_str, btn3_x + (btn_w - (int)b3_str.len * lm.char_width) / 2, btn_y + (btn_h - lm.char_height) / 2, lm.font_scale, hover3 ? config::theme.text_bright : config::theme.text_muted);
	}
	else if (ed.modal.kind == REPLACE)
	{
		int input_w  = modal_w - 32;
		int input1_y = modal_y + 14 + lm.char_height + 6;
		int input2_y = input1_y + input_box_h + 10;
		int max_vis_chars = math::max(1, (input_w - 16) / lm.char_width);

		ed.modal.input.ensure_cursor_visible(max_vis_chars);
		ed.modal.replace_input.ensure_cursor_visible(max_vis_chars);

		gfx::draw_rect(modal_x + 16, input1_y, input_w, input_box_h, config::theme.bg);
		Color border1_col = (ed.modal.focus_field == 0) ? config::theme.accent_blue : config::theme.gutter_border;
		gfx::draw_rect_lines(modal_x + 16, input1_y, input_w, input_box_h, border1_col);

		gfx::begin_scissor(modal_x + 18, input1_y, input_w - 4, input_box_h);
		int text_draw1_y = input1_y + (input_box_h - lm.char_height) / 2;
		int text_draw1_x = modal_x + 24 - ed.modal.input.scroll_col * lm.char_width;
		font::draw_text(ed.modal.input.view(), text_draw1_x, text_draw1_y, lm.font_scale, config::theme.text_bright);
		if (ed.modal.focus_field == 0 && ed.cursor_visible)
		{
			int cursor_col = (int)conv::utf8_codepoints(ed.modal.input.view()[:ed.modal.input.cursor_pos]);
			int cur_x = modal_x + 24 + (cursor_col - ed.modal.input.scroll_col) * lm.char_width;
			gfx::draw_rect(cur_x, text_draw1_y, 2, lm.char_height, config::theme.cursor);
		}
		gfx::end_scissor();

		gfx::draw_rect(modal_x + 16, input2_y, input_w, input_box_h, config::theme.bg);
		Color border2_col = (ed.modal.focus_field == 1) ? config::theme.accent_blue : config::theme.gutter_border;
		gfx::draw_rect_lines(modal_x + 16, input2_y, input_w, input_box_h, border2_col);

		gfx::begin_scissor(modal_x + 18, input2_y, input_w - 4, input_box_h);
		int text_draw2_y = input2_y + (input_box_h - lm.char_height) / 2;
		int text_draw2_x = modal_x + 24 - ed.modal.replace_input.scroll_col * lm.char_width;
		font::draw_text(ed.modal.replace_input.view(), text_draw2_x, text_draw2_y, lm.font_scale, config::theme.text_bright);
		if (ed.modal.focus_field == 1 && ed.cursor_visible)
		{
			int cursor_col = (int)conv::utf8_codepoints(ed.modal.replace_input.view()[:ed.modal.replace_input.cursor_pos]);
			int cur_x = modal_x + 24 + (cursor_col - ed.modal.replace_input.scroll_col) * lm.char_width;
			gfx::draw_rect(cur_x, text_draw2_y, 2, lm.char_height, config::theme.cursor);
		}
		gfx::end_scissor();
	}
	else
	{
		int input_y = modal_y + 14 + lm.char_height + 8;
		int input_w = modal_w - 32;
		int max_vis_chars = math::max(1, (input_w - 16) / lm.char_width);

		ed.modal.input.ensure_cursor_visible(max_vis_chars);

		gfx::draw_rect(modal_x + 16, input_y, input_w, input_box_h, config::theme.bg);
		gfx::draw_rect_lines(modal_x + 16, input_y, input_w, input_box_h, config::theme.gutter_border);

		gfx::begin_scissor(modal_x + 18, input_y, input_w - 4, input_box_h);
		int text_draw_y = input_y + (input_box_h - lm.char_height) / 2;
		int text_draw_x = modal_x + 24 - ed.modal.input.scroll_col * lm.char_width;
		font::draw_text(ed.modal.input.view(), text_draw_x, text_draw_y, lm.font_scale, config::theme.text_bright);

		if (ed.cursor_visible)
		{
			int cursor_col = (int)conv::utf8_codepoints(ed.modal.input.view()[:ed.modal.input.cursor_pos]);
			int cur_x = modal_x + 24 + (cursor_col - ed.modal.input.scroll_col) * lm.char_width;
			gfx::draw_rect(cur_x, text_draw_y, 2, lm.char_height, config::theme.cursor);
		}
		gfx::end_scissor();

		if (ed.modal.kind == QUICK_OPEN || ed.modal.kind == GLOBAL_GREP || ed.modal.kind == SYMBOL_OUTLINE)
		{
			int list_y   = input_y + input_box_h + 10;
			int list_h   = modal_y + modal_h - list_y - config::LAYOUT_METRICS.modal_padding_y;
			int row_h    = math::max(config::LAYOUT_METRICS.modal_row_h_min, lm.line_height);
			int max_rows = math::max(1, list_h / row_h);
			ed.modal.picker.clamp_view(max_rows);

			gfx::draw_rect(modal_x + config::LAYOUT_METRICS.modal_padding_x, list_y, input_w, list_h, config::theme.bg);
			gfx::draw_rect_lines(modal_x + config::LAYOUT_METRICS.modal_padding_x, list_y, input_w, list_h, config::theme.gutter_border);
			gfx::begin_scissor(modal_x + config::LAYOUT_METRICS.modal_padding_x, list_y, input_w, list_h);

			for (int r = 0; r < max_rows; r++)
			{
				int idx = r + ed.modal.picker.scroll_offset;
				if (idx >= (int)ed.modal.picker.items.len()) break;
				int ry = list_y + r * row_h + 2;
				bool is_selected = (idx == ed.modal.picker.selected_index);
				if (is_selected)
				{
					gfx::draw_rect(modal_x + 18, ry - 1, input_w - 4, row_h - 2, config::theme.selection_bg);
				}

				PickerItem item = ed.modal.picker.items[(sz)idx];
				Color text_col = is_selected ? config::theme.text_bright : config::theme.text;
				int draw_text_y = ry + (row_h - lm.char_height) / 2;

				if (item.detail.len > 0)
				{
					font::draw_text(item.detail, modal_x + 24, draw_text_y, lm.font_scale, config::theme.accent_blue);
					int offset_x = (int)(item.detail.len + 1) * lm.char_width;
					font::draw_text(item.label, modal_x + 24 + offset_x, draw_text_y, lm.font_scale, text_col);
				}
				else
				{
					font::draw_text(item.label, modal_x + 24, draw_text_y, lm.font_scale, text_col);
				}
			}
			gfx::end_scissor();
		}
	}
}

struct MatchByteInfo
{
	bool is_match;
	bool is_start;
	bool is_end;
}

fn void render(Editor* ed, int screen_w, int height, LayoutMetrics* lm)
{
	Tab* tab = ed.active_tab();
	Document* doc = &tab.doc;

	gfx::begin_frame();
	gfx::clear_background(config::theme.bg);

	// Tab Bar
	gfx::draw_rect(0, 0, screen_w, lm.tab_bar_height, config::theme.tab_bg);
	gfx::draw_rect(0, lm.tab_bar_height - 1, screen_w, 1, config::theme.tab_border);

	int tab_x       = 0;
	int tab_h       = lm.tab_bar_height;
	int close_box_w = lm.char_width * 2 + 10;

	for (sz i = 0; i < ed.tabs.len(); i++)
	{
		Tab* t = &ed.tabs[i];
		bool is_active = ((int)i == ed.active_tab_index);

		String name_str = t.doc.filepath.file_tbasename() ?? t.doc.filepath;
		if (name_str.len == 0) name_str = "untitled.c3";

		String tab_title = string::tformat("%d: %s%s", i + 1, name_str, t.doc.is_modified ? " *" : "");
		int title_w      = (int)tab_title.len * lm.char_width;
		int tab_w        = title_w + close_box_w + config::LAYOUT_METRICS.tab_extra_padding;

		if (tab_x + tab_w > screen_w - config::LAYOUT_METRICS.tab_min_w_gap)
		{
			tab_w = screen_w - config::LAYOUT_METRICS.tab_min_w_gap - tab_x;
		}
		if (tab_w <= close_box_w + 10) break;

		Color bg_col = is_active ? config::theme.tab_active_bg : config::theme.tab_bg;
		gfx::draw_rect(tab_x, 0, tab_w, tab_h, bg_col);
		gfx::draw_rect(tab_x + tab_w - 1, 0, 1, tab_h, config::theme.tab_border);

		if (is_active)
		{
			gfx::draw_rect(tab_x, 0, tab_w, 2, config::theme.accent_blue);
		}

		Color txt_col = is_active ? config::theme.text_bright : config::theme.text_muted;
		int txt_y     = (tab_h - lm.char_height) / 2;

		int label_w = tab_w - close_box_w - 8;
		if (label_w > 0)
		{
			gfx::begin_scissor(tab_x + 8, 0, label_w, tab_h);
			font::draw_text(tab_title, tab_x + 8, txt_y, lm.font_scale, txt_col);
			gfx::end_scissor();
		}

		int close_x   = tab_x + tab_w - close_box_w;
		int x_glyph_x = close_x + (close_box_w - lm.char_width) / 2;
		font::draw_char('x', x_glyph_x, txt_y, lm.font_scale, is_active ? config::theme.text : config::theme.text_muted);

		tab_x += tab_w;
	}

	// Gutter and Git Diffs
	gfx::draw_rect(0, lm.tab_bar_height, lm.gutter_width - config::LAYOUT_METRICS.gutter_border_w, lm.editor_h, config::theme.gutter_bg);
	gfx::draw_rect(lm.gutter_width - config::LAYOUT_METRICS.gutter_border_w, lm.tab_bar_height, config::LAYOUT_METRICS.gutter_border_w, lm.editor_h, config::theme.gutter_border);

	Cursor* primary = doc.primary_cursor();
	LineCol cur_lc  = doc.get_line_col(primary.pos);
	int cline       = cur_lc.line;
	int ccol        = cur_lc.col;

	for (int l = 0; l < lm.visible_lines; l++)
	{
		int line_idx = l + tab.scroll_line;
		if (line_idx >= doc.get_total_lines()) break;

		int gy = lm.text_start_y + l * lm.line_height;

		if (config::settings.show_git_gutter)
		{
			GitLineStatus st = ed.workspace.git.get_status(line_idx);
			int gx = lm.gutter_width - config::LAYOUT_METRICS.gutter_border_w - 5;
			switch (st)
			{
				case ADDED:
					gfx::draw_rect(gx, gy, 3, lm.line_height, config::theme.git_added);
				case MODIFIED:
					gfx::draw_rect(gx, gy, 3, lm.line_height, config::theme.git_modified);
				case DELETED:
					gfx::draw_triangle(
						{ (float)gx, (float)gy },
						{ (float)gx, (float)gy + 6.0f },
						{ (float)(gx + 5), (float)gy + 3.0f },
						config::theme.git_deleted
					);
				default: break;
			}
		}

		Color gcol = (line_idx == cline) ? config::theme.accent_blue : config::theme.text_muted;
		char[32] gbuf;
		String gs    = string::bformat(&gbuf, "%d", line_idx + 1);
		int text_w   = (int)gs.len * lm.char_width;
		int draw_x   = lm.gutter_width - config::LAYOUT_METRICS.gutter_border_w - 8 - text_w - 6;
		font::draw_text(gs, draw_x, gy, lm.font_scale, gcol);
	}

	// Editor Text Canvas
	gfx::begin_scissor(lm.text_start_x, lm.text_start_y, lm.editor_w, lm.editor_h - 12);

	foreach (&cur : doc.cursors)
	{
		int active_rel_line = doc.get_line(cur.pos) - tab.scroll_line;
		if (active_rel_line >= 0 && active_rel_line < lm.visible_lines)
		{
			int hl_y = lm.text_start_y + active_rel_line * lm.line_height;
			gfx::draw_rect(lm.text_start_x - 8, hl_y, lm.editor_w + 8, lm.line_height, config::theme.line_highlight);
		}
	}

	int start_line = math::clamp(tab.scroll_line, 0, math::max(0, doc.get_total_lines() - 1));
	int end_line   = math::min(doc.get_total_lines(), start_line + lm.visible_lines + 1);

	// Indentation Guides
	if (config::settings.show_indent_guides)
	{
		int guide_start_l = math::max(0, start_line - 64);
		int guide_end_l   = math::min(doc.get_total_lines(), end_line + 64);

		for (int l = guide_start_l; l < guide_end_l; l++)
		{
			BytePos ls = doc.get_line_start_of_line(l);
			BytePos le = doc.get_line_end(ls);
			if (ls >= le) continue;

			String l_str = doc.table.get_slice(ls, le, tmem);
			sz first_non_ws = 0;
			while (first_non_ws < l_str.len && (l_str[first_non_ws] == ' ' || l_str[first_non_ws] == '\t')) first_non_ws++;
			int scope_col = doc.get_col(ls + first_non_ws);

			for (sz p = 0; p < l_str.len; p++)
			{
				if (l_str[p] == '{')
				{
					int depth = 1;
					BytePos close_pos = 0;
					BytePos max_scan = math::min(doc.table.len(), ls + p + 16384);
					for (BytePos cp = ls + p + 1; cp < max_scan; cp = c3ed::get_next_char_pos(&doc.table, cp))
					{
						char ch = doc.table.char_at(cp);
						if (ch == '{')
						{
							depth++;
						}
						else if (ch == '}')
						{
							depth--;
							if (depth == 0)
							{
								close_pos = cp;
								break;
							}
						}
					}
					if (close_pos > 0)
					{
						int l_close = doc.get_line(close_pos);
						if (l_close > l)
						{
							int sx = lm.text_start_x + (scope_col - tab.scroll_col) * lm.char_width + (lm.char_width / 2);
							int top_l = math::max(l + 1, start_line);
							int bot_l = math::min(l_close, end_line);

							if (bot_l >= top_l)
							{
								int sy_start = lm.text_start_y + (top_l - tab.scroll_line) * lm.line_height;
								int sy_end   = lm.text_start_y + (bot_l - tab.scroll_line) * lm.line_height;
								bool is_active_scope = (cline >= l && cline <= l_close);
								Color scol = is_active_scope ? config::theme.indent_guide_active : config::theme.indent_guide;
								gfx::draw_line(sx, sy_start, sx, sy_end, scol);
							}
						}
					}
				}
			}
		}
	}

	TokenType[1024] token_scratch;
	MatchByteInfo[1024] match_info;

	bool has_search_query = (ed.modal.kind == FIND || ed.modal.kind == REPLACE) && ed.modal.input.length > 0;
	String search_query = has_search_query ? ed.modal.input.view() : "";

	for (int l = start_line; l < end_line; l++)
	{
		int rel_line = l - tab.scroll_line;
		if (rel_line < 0 || rel_line >= lm.visible_lines) continue;

		BytePos ls = doc.get_line_start_of_line(l);
		BytePos le = doc.get_line_end(ls);
		String line_str = doc.table.get_slice(ls, le, tmem);

		LineState start_state = (l == 0) ? NORMAL
			: ((sz)l - 1 < doc.line_states.len() ? doc.line_states[(sz)l - 1] : NORMAL);

		TokenType[] line_tokens = (line_str.len <= 1024) ? token_scratch[:line_str.len]
			: alloc::alloc_array(tmem, TokenType, line_str.len);

		syntax::lex_slice(line_str, start_state, line_tokens);

		sz max_track = math::min(line_str.len + 1, (sz)1024);
		mem::clear(&match_info, max_track * MatchByteInfo::size);

		if (has_search_query && search_query.len > 0 && line_str.len >= search_query.len)
		{
			sz qlen = search_query.len;
			sz scan_idx = 0;
			while (scan_idx + qlen <= line_str.len)
			{
				bool is_match = ed.modal.search_case_sensitive
					? (line_str[scan_idx:qlen] == search_query)
					: (line_str[scan_idx:qlen].to_lower_tcopy() == search_query.to_lower_tcopy());

				if (is_match)
				{
					sz end_m = math::min(scan_idx + qlen, (sz)1024);
					for (sz m = scan_idx; m < end_m; m++)
					{
						match_info[m].is_match = true;
					}
					if (scan_idx < 1024) match_info[scan_idx].is_start = true;
					if (end_m > 0 && end_m <= 1024) match_info[end_m - 1].is_end = true;
					scan_idx += qlen;
				}
				else
				{
					scan_idx++;
				}
			}
		}

		int py = lm.text_start_y + rel_line * lm.line_height;
		int cur_col = 0;
		sz p = 0;

		while (p < line_str.len)
		{
			char c = line_str[p];
			int rel_col = cur_col - tab.scroll_col;
			int px = lm.text_start_x + rel_col * lm.char_width;

			BytePos global_p = ls + p;
			sz char_bytes = 1;
			while (p + char_bytes < line_str.len && (line_str[p + char_bytes] & 0xC0) == 0x80) char_bytes++;
			BytePos global_next_p = global_p + char_bytes;

			bool is_selected = false;
			foreach (&cur : doc.cursors)
			{
				if (cur.has_selection() && global_p < cur.sel_end() && global_next_p > cur.sel_start())
				{
					is_selected = true;
					break;
				}
			}

			bool is_search_match = (p < 1024 && match_info[p].is_match);
			bool is_match_start  = (p < 1024 && match_info[p].is_start);
			bool is_match_end    = (p + char_bytes - 1 < 1024 && match_info[p + char_bytes - 1].is_end);
			TokenType tok_type   = line_tokens[p];

			switch (c)
			{
				case '\r':
					p++;
				case '\t':
					int tab_spaces = config::settings.tab_size - (cur_col % config::settings.tab_size);
					int tab_w = lm.char_width * tab_spaces;
					if (px + tab_w >= lm.text_start_x && px < screen_w)
					{
						if (is_selected)
						{
							gfx::draw_rect(px, py, tab_w, lm.line_height, config::theme.selection_bg);
						}
						else if (is_search_match)
						{
							Color match_bg     = { 250, 204, 21, 95 };
							Color match_border = { 250, 204, 21, 200 };
							gfx::draw_rect(px, py, tab_w, lm.line_height, match_bg);
							gfx::draw_line(px, py, px + tab_w, py, match_border);
							gfx::draw_line(px, py + lm.line_height - 1, px + tab_w, py + lm.line_height - 1, match_border);
							if (is_match_start) gfx::draw_line(px, py, px, py + lm.line_height, match_border);
							if (is_match_end)   gfx::draw_line(px + tab_w - 1, py, px + tab_w - 1, py + lm.line_height, match_border);
						}
						else
						{
							font::draw_tab_guide(px, py, tab_spaces, lm.char_width, lm.font_scale, config::theme.tab_guide);
						}
					}
					cur_col += tab_spaces;
					p++;
				default:
					Char32 codepoint = (Char32)c;
					if (char_bytes > 1)
					{
						sz read_len = char_bytes;
						codepoint = conv::utf8_to_char32(&line_str[p], &read_len) ?? (Char32)c;
					}

					if (px + lm.char_width >= lm.text_start_x && px < screen_w)
					{
						if (is_selected)
						{
							gfx::draw_rect(px, py, lm.char_width, lm.line_height, config::theme.selection_bg);
							font::draw_char(codepoint, px, py, lm.font_scale, config::theme.text_bright);
						}
						else if (is_search_match)
						{
							Color match_bg     = { 250, 204, 21, 95 };
							Color match_border = { 250, 204, 21, 200 };
							gfx::draw_rect(px, py, lm.char_width, lm.line_height, match_bg);
							gfx::draw_line(px, py, px + lm.char_width, py, match_border);
							gfx::draw_line(px, py + lm.line_height - 1, px + lm.char_width, py + lm.line_height - 1, match_border);

							if (is_match_start) gfx::draw_line(px, py, px, py + lm.line_height, match_border);
							if (is_match_end)   gfx::draw_line(px + lm.char_width - 1, py, px + lm.char_width - 1, py + lm.line_height, match_border);
							font::draw_char(codepoint, px, py, lm.font_scale, config::theme.text_bright);
						}
						else
						{
							font::draw_char(codepoint, px, py, lm.font_scale, tok_type.color);
						}
					}
					cur_col++;
					p += char_bytes;
			}
		}

		if (le < doc.table.len())
		{
			bool newline_selected = false;
			foreach (&cur : doc.cursors)
			{
				if (cur.has_selection() && le < cur.sel_end() && le >= cur.sel_start())
				{
					newline_selected = true;
					break;
				}
			}
			if (newline_selected)
			{
				int px = lm.text_start_x + (cur_col - tab.scroll_col) * lm.char_width;
				if (px >= lm.text_start_x && px < screen_w)
				{
					gfx::draw_rect(px, py, lm.char_width, lm.line_height, config::theme.selection_bg);
				}
			}
		}
	}

	// Diagnostic Squiggles
	for (int l = start_line; l < end_line; l++)
	{
		Diagnostic*? d_opt = ed.workspace.diagnostics.get_at(doc.filepath, l + 1);
		if (try d = d_opt)
		{
			if (d != null)
			{
				int sy = lm.text_start_y + (l - tab.scroll_line + 1) * lm.line_height - 2;
				int sx = lm.text_start_x + (d.col - 1 - tab.scroll_col) * lm.char_width;
				Color scol = (d.severity == ERROR) ? config::theme.squiggle_error : config::theme.squiggle_warn;

				for (int wx = sx; wx < sx + 30; wx += 4)
				{
					gfx::draw_line(wx, sy, wx + 2, sy - 2, scol);
					gfx::draw_line(wx + 2, sy - 2, wx + 4, sy, scol);
				}
			}
		}
	}

	// Render Cursors
	if (ed.cursor_visible && ed.modal.kind == NONE)
	{
		foreach (&cur : doc.cursors)
		{
			int cur_l        = doc.get_line(cur.pos);
			int cur_c        = doc.get_col(cur.pos);
			int active_rel_l = cur_l - tab.scroll_line;

			if (active_rel_l >= 0 && active_rel_l < lm.visible_lines)
			{
				int cx = lm.text_start_x + (cur_c - tab.scroll_col) * lm.char_width;
				int cy = lm.text_start_y + active_rel_l * lm.line_height;
				gfx::draw_rect(cx, cy, 2, lm.line_height, config::theme.cursor);
			}
		}
	}

	gfx::end_scissor();

	// Minimap
	if (config::settings.show_minimap && lm.minimap_w > 0)
	{
		int mm_y = lm.tab_bar_height;
		int mm_h = lm.editor_h;
		gfx::draw_rect(lm.minimap_x, mm_y, lm.minimap_w, mm_h, config::theme.minimap_bg);

		int total_doc_lines = doc.get_total_lines();
		int mm_line_h = config::LAYOUT_METRICS.minimap_line_h;
		int total_mm_h = total_doc_lines * mm_line_h;
		int max_editor_scroll = math::max(1, total_doc_lines - lm.visible_lines);
		float scroll_ratio = math::clamp((float)tab.scroll_line / (float)max_editor_scroll, 0.0f, 1.0f);

		int mm_scroll_y = 0;
		if (total_mm_h > mm_h)
		{
			mm_scroll_y = (int)(scroll_ratio * (float)(total_mm_h - mm_h));
		}

		int mm_start_l = mm_scroll_y / mm_line_h;
		int mm_end_l   = math::min(total_doc_lines, mm_start_l + (mm_h / mm_line_h) + 1);

		gfx::begin_scissor(lm.minimap_x, mm_y, lm.minimap_w, mm_h);

		for (int l = mm_start_l; l < mm_end_l; l++)
		{
			int my = mm_y + l * mm_line_h - mm_scroll_y;
			if (my < mm_y || my >= mm_y + mm_h) continue;

			if (config::settings.show_git_gutter)
			{
				GitLineStatus st = ed.workspace.git.get_status(l);
				switch (st)
				{
					case ADDED:
						gfx::draw_rect(lm.minimap_x, my, 3, mm_line_h, config::theme.git_added);
					case MODIFIED:
						gfx::draw_rect(lm.minimap_x, my, 3, mm_line_h, config::theme.git_modified);
					case DELETED:
						gfx::draw_rect(lm.minimap_x, my, 5, 2, config::theme.git_deleted);
					default: break;
				}
			}

			BytePos ls = doc.get_line_start_of_line(l);
			BytePos le = doc.get_line_end(ls);
			int line_len = (int)math::min((sz)lm.minimap_w - 6, (le - ls) / 2);
			if (line_len > 0)
			{
				gfx::draw_rect(lm.minimap_x + 4, my, line_len, mm_line_h, config::theme.text_muted);
			}
		}

		foreach (match_l : ed.modal.cached_match_lines)
		{
			int my = mm_y + match_l * mm_line_h - mm_scroll_y;
			if (my >= mm_y && my < mm_y + mm_h)
			{
				gfx::draw_rect(lm.minimap_x, my, lm.minimap_w, 2, config::theme.accent_yellow);
			}
		}

		int vp_y = mm_y + tab.scroll_line * mm_line_h - mm_scroll_y;
		int vp_h = math::max(config::LAYOUT_METRICS.minimap_min_thumb_h, lm.visible_lines * mm_line_h);
		vp_y = math::clamp(vp_y, mm_y, mm_y + mm_h - vp_h);

		gfx::draw_rect(lm.minimap_x, vp_y, lm.minimap_w, vp_h, config::theme.minimap_viewport);
		gfx::draw_rect_lines(lm.minimap_x, vp_y, lm.minimap_w, vp_h, config::theme.accent_blue);

		gfx::end_scissor();
	}

	// Scrollbar
	if (doc.get_total_lines() > lm.visible_lines)
	{
		int sb_w           = config::LAYOUT_METRICS.scrollbar_w;
		int sb_x           = screen_w - sb_w - 2;
		int sb_y           = lm.tab_bar_height;
		int sb_h           = lm.editor_h;
		float thumb_h      = math::max(config::LAYOUT_METRICS.scrollbar_min_thumb_h, (float)sb_h * (float)lm.visible_lines / (float)doc.get_total_lines());
		float max_scroll   = (float)(doc.get_total_lines() - lm.visible_lines);
		float scrollable_h = (float)sb_h - thumb_h;
		float thumb_y      = (float)sb_y + (scrollable_h * (float)tab.scroll_line / max_scroll);

		gfx::draw_rect(sb_x, sb_y, sb_w, sb_h, config::theme.header_bg);
		Color thumb_col = ed.scrollbar_dragging ? config::theme.scrollbar_act : config::theme.scrollbar;
		gfx::draw_rect(sb_x + 1, (int)thumb_y, sb_w - 2, (int)thumb_h, thumb_col);

		if (config::settings.show_git_gutter)
		{
			foreach (&hunk : ed.workspace.git.hunks)
			{
				int tick_y = sb_y + (int)(((float)hunk.line_start / (float)doc.get_total_lines()) * (float)sb_h);
				Color gcol = (hunk.status == ADDED)
					? config::theme.git_added
					: ((hunk.status == DELETED) ? config::theme.git_deleted : config::theme.git_modified);
				gfx::draw_rect(sb_x, tick_y, sb_w, 2, gcol);
			}
		}

		foreach (match_l : ed.modal.cached_match_lines)
		{
			int tick_y = sb_y + (int)(((float)match_l / (float)doc.get_total_lines()) * (float)sb_h);
			gfx::draw_rect(sb_x, tick_y, sb_w, 2, config::theme.accent_yellow);
		}

		foreach (&d : ed.workspace.diagnostics.items)
		{
			if (d.filepath.ends_with(doc.filepath) || doc.filepath.ends_with(d.filepath))
			{
				int tick_y = sb_y + (int)(((float)d.line / (float)doc.get_total_lines()) * (float)sb_h);
				Color tcol = (d.severity == ERROR) ? config::theme.accent_red : config::theme.accent_yellow;
				gfx::draw_rect(sb_x, tick_y, sb_w, 2, tcol);
			}
		}
	}

	// Autocomplete Popup
	if (ed.autocomplete.is_active && ed.autocomplete.items.len() > 0)
	{
		int pop_w = config::LAYOUT_METRICS.popup_w;
		int row_h = lm.char_height + 6;
		int pop_rows = math::min(config::LAYOUT_METRICS.popup_max_rows, (int)ed.autocomplete.items.len());
		int pop_h = pop_rows * row_h + 8;

		int pop_x = lm.text_start_x + (ccol - tab.scroll_col) * lm.char_width;
		int pop_y = lm.text_start_y + (cline - tab.scroll_line + 1) * lm.line_height;

		if (pop_x + pop_w > screen_w - 20) pop_x = screen_w - pop_w - 20;
		if (pop_y + pop_h > height - lm.footer_height) pop_y = pop_y - pop_h - lm.line_height;

		gfx::draw_rect(pop_x - 2, pop_y - 2, pop_w + 4, pop_h + 4, config::theme.popup_border);
		gfx::draw_rect(pop_x, pop_y, pop_w, pop_h, config::theme.popup_bg);

		for (int r = 0; r < pop_rows; r++)
		{
			int item_idx = r + ed.autocomplete.scroll_offset;
			if (item_idx >= (int)ed.autocomplete.items.len()) break;

			CompletionItem* it = &ed.autocomplete.items[(sz)item_idx];
			int ry = pop_y + 4 + r * row_h;

			if (item_idx == ed.autocomplete.selected_index)
			{
				gfx::draw_rect(pop_x + 2, ry, pop_w - 4, row_h, config::theme.popup_selected);
			}

			String kind_tag = "[v]";
			Color tag_col = config::theme.accent_yellow;
			switch (it.kind)
			{
				case FUNCTION:   kind_tag = "[fn]";     tag_col = config::theme.accent_blue;
				case STRUCT:     kind_tag = "[struct]"; tag_col = config::theme.accent_green;
				case UNION:      kind_tag = "[union]";  tag_col = config::theme.accent_green;
				case ENUM:       kind_tag = "[enum]";   tag_col = config::theme.accent_green;
				case BITSTRUCT:  kind_tag = "[bitst]";  tag_col = config::theme.accent_green;
				case MACRO:      kind_tag = "[macro]";  tag_col = config::theme.accent_red;
				case TYPE_ALIAS: kind_tag = "[type]";   tag_col = config::theme.accent_green;
				case CONSTANT:   kind_tag = "[const]";  tag_col = config::theme.accent_yellow;
				case FAULT:      kind_tag = "[fault]";  tag_col = config::theme.accent_red;
				case FIELD:      kind_tag = "[field]";  tag_col = config::theme.accent_blue;
				default:         kind_tag = "[var]";    tag_col = config::theme.text_muted;
			}

			font::draw_text(kind_tag, pop_x + 6, ry + 2, lm.font_scale, tag_col);
			font::draw_text(it.label, pop_x + 6 + 8 * lm.char_width, ry + 2, lm.font_scale, config::theme.text_bright);
		}
	}

	// Bottom Terminal Panel
	if (ed.terminal.is_open && lm.terminal_height > 0)
	{
		int ty = (int)lm.terminal_rect.y;
		int th = lm.terminal_height;

		gfx::draw_rect(0, ty, screen_w, th, config::theme.panel_bg);
		gfx::draw_rect(0, ty, screen_w, 2, config::theme.accent_blue);

		font::draw_text("[BUILD & RUN OUTPUT] (Ctrl+~ to toggle | Click+Drag to Copy)", 12, ty + 6, lm.font_scale, config::theme.accent_blue);

		gfx::begin_scissor(12, ty + lm.line_height + 4, screen_w - 24, th - lm.line_height - 8);
		int max_term_lines = (th - lm.line_height - 8) / lm.line_height;
		int total_tlines   = (int)ed.terminal.lines.len();
		int start_idx      = math::clamp(ed.terminal.scroll_line - max_term_lines + 1, 0, math::max(0, total_tlines - max_term_lines));

		for (int idx = start_idx; idx < total_tlines && idx < start_idx + max_term_lines; idx++)
		{
			int row_y = ty + lm.line_height + 8 + (idx - start_idx) * lm.line_height;
			String line_text = ed.terminal.lines[(sz)idx];

			if (ed.terminal.has_selection())
			{
				int s_line = math::min(ed.terminal.sel_start_line, ed.terminal.sel_end_line);
				int e_line = math::max(ed.terminal.sel_start_line, ed.terminal.sel_end_line);
				if (idx >= s_line && idx <= e_line)
				{
					int s_col = (idx == s_line) ? math::min(ed.terminal.sel_start_col, ed.terminal.sel_end_col) : 0;
					int e_col = (idx == e_line) ? math::max(ed.terminal.sel_start_col, ed.terminal.sel_end_col) : (int)line_text.len;
					int hl_x  = 14 + s_col * lm.char_width;
					int hl_w  = math::max(1, (e_col - s_col)) * lm.char_width;
					gfx::draw_rect(hl_x, row_y, hl_w, lm.line_height, config::theme.selection_bg);
				}
			}

			Color tcol = config::theme.text;
			if (line_text.contains("Error") || line_text.contains("error"))
			{
				tcol = config::theme.accent_red;
			}
			else if (line_text.contains("Warning") || line_text.contains("warning"))
			{
				tcol = config::theme.accent_yellow;
			}
			font::draw_text(line_text, 14, row_y, lm.font_scale, tcol);
		}
		gfx::end_scissor();
	}

	// Modals
	if (ed.modal.kind != NONE)
	{
		render_modal(ed, screen_w, height, lm);
	}

	int footer_y      = (int)lm.footer_rect.y;
	int footer_text_y = footer_y + (lm.footer_height - lm.char_height) / 2;
	gfx::draw_rect(0, footer_y, screen_w, lm.footer_height, config::theme.footer_bg);

	String file_disp = doc.filepath.len > 0 ? doc.filepath : "untitled.c3";
	String mod_str   = doc.is_modified ? " [+]" : "";
	String save_str  = (ed.save_msg_timer > 0.0f) ? " [SAVED]" : "";
	String left_s    = string::tformat("%s%s%s", file_disp, mod_str, save_str);
	font::draw_text(left_s, 12, footer_text_y, lm.font_scale, config::theme.text_bright);

	int mid_x = screen_w / 2 - 120;
	if (doc.cursors.len() > 1)
	{
		String cur_count_str = string::tformat("[%d CARETS]", doc.cursors.len());
		font::draw_text(cur_count_str, mid_x, footer_text_y, lm.font_scale, config::theme.accent_blue);
		mid_x += ((int)cur_count_str.len + 2) * lm.char_width;
	}

	Cursor* pcur = doc.primary_cursor();
	sz sel_bytes = pcur.pos > pcur.anchor ? pcur.pos - pcur.anchor : pcur.anchor - pcur.pos;
	if (sel_bytes > 0)
	{
		DString sel_ds;
		sel_ds.tinit();
		doc.table.append_range_to_dstring(&sel_ds, pcur.sel_start(), pcur.sel_end());
		sz sel_count = conv::utf8_codepoints(sel_ds.str_view());
		String sel_s = string::tformat("SEL: %d", sel_count);
		font::draw_text(sel_s, mid_x, footer_text_y, lm.font_scale, config::theme.accent_yellow);
	}

	String right_str = string::tformat(
		"TAB %d/%d  LN: %d  COL: %d   LINES: %d  BYTES: %d",
		ed.active_tab_index + 1,
		ed.tabs.len(),
		cline + 1,
		ccol + 1,
		doc.get_total_lines(),
		doc.table.len()
	);
	int right_w = (int)right_str.len * lm.char_width;
	font::draw_text(right_str, screen_w - right_w - 12, footer_text_y, lm.font_scale, config::theme.header_muted);

	gfx::end_frame();
}
