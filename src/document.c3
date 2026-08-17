module c3ed;
import std;

alias BytePos = sz;

struct LineCol
{
	int line;
	int col;
}

struct TextRange
{
	BytePos start;
	BytePos end;
}

struct Cursor
{
	BytePos pos;
	BytePos anchor;
	int target_col;
}

fn bool Cursor.has_selection(&self) @inline => self.pos != self.anchor;
fn BytePos Cursor.sel_start(&self) @inline => math::min(self.pos, self.anchor);
fn BytePos Cursor.sel_end(&self) @inline => math::max(self.pos, self.anchor);

fn int compare_cursors(Cursor* a, Cursor* b)
{
	switch
	{
		case a.pos < b.pos: return -1;
		case a.pos > b.pos: return 1;
		case a.anchor < b.anchor: return -1;
		case a.anchor > b.anchor: return 1;
		default: return 0;
	}
}

fn bool is_word_char(char c) => c.is_alnum() || c == '_' || (c & 0x80) != 0;
fn bool is_symbol_char(char c) => !is_word_char(c) && c != '\n' && c != '\r' && c != ' ' && c != '\t';

fn BytePos get_prev_char_pos(PieceTable* pt, BytePos pos)
{
	if (pos == 0) return 0;
	BytePos len = pt.len();
	BytePos p   = math::min(pos, len) - 1;
	while (p > 0 && (pt.char_at(p) & 0xC0) == 0x80) p--;
	return p;
}

fn BytePos get_next_char_pos(PieceTable* pt, BytePos pos)
{
	BytePos len = pt.len();
	if (pos >= len) return len;
	BytePos p = pos + 1;
	while (p < len && (pt.char_at(p) & 0xC0) == 0x80) p++;
	return p;
}

fn BytePos get_prev_word_pos(PieceTable* pt, BytePos pos)
{
	if (pos == 0) return 0;
	BytePos len = pt.len();
	BytePos p   = math::min(pos, len);
	while (p > 0 && p < len && (pt.char_at(p) & 0xC0) == 0x80) p--;
	while (p > 0 && !is_word_char(pt.char_at(p - 1))) p = get_prev_char_pos(pt, p);
	while (p > 0 && is_word_char(pt.char_at(p - 1))) p = get_prev_char_pos(pt, p);
	return p;
}

fn BytePos get_next_word_pos(PieceTable* pt, BytePos pos)
{
	BytePos len = pt.len();
	if (pos >= len) return len;
	BytePos p = pos;
	while (p < len && (pt.char_at(p) & 0xC0) == 0x80) p++;
	while (p < len && !is_word_char(pt.char_at(p))) p = get_next_char_pos(pt, p);
	while (p < len && is_word_char(pt.char_at(p))) p = get_next_char_pos(pt, p);
	return p;
}

fn TextRange get_word_bounds(PieceTable* pt, BytePos pos)
{
	BytePos len = pt.len();
	if (len == 0) return { 0, 0 };

	BytePos p = math::min(pos, len);
	while (p > 0 && p < len && (pt.char_at(p) & 0xC0) == 0x80) p--;

	if (p == len || (p < len && !is_word_char(pt.char_at(p))))
	{
		if (pos > 0)
		{
			BytePos prev_p = get_prev_char_pos(pt, pos);
			if (is_word_char(pt.char_at(prev_p)))
			{
				p = prev_p;
			}
		}
	}

	if (p >= len) p = len - 1;
	while (p > 0 && (pt.char_at(p) & 0xC0) == 0x80) p--;
	char c = pt.char_at(p);

	switch
	{
		case is_word_char(c):
			BytePos start = p;
			while (start > 0 && is_word_char(pt.char_at(start - 1))) start = get_prev_char_pos(pt, start);
			BytePos end = p;
			while (end < len && is_word_char(pt.char_at(end))) end = get_next_char_pos(pt, end);
			return { start, end };
		case c == '\n' || c == '\r' || c == ' ' || c == '\t':
			return { p, p };
		default:
			BytePos start = p;
			while (start > 0 && is_symbol_char(pt.char_at(start - 1))) start = get_prev_char_pos(pt, start);
			BytePos end = p;
			while (end < len && is_symbol_char(pt.char_at(end))) end = get_next_char_pos(pt, end);
			if (start == end) end = get_next_char_pos(pt, start);
			return { start, end };
	}
}

struct Document
{
	String filepath;
	bool is_file_specified;
	bool is_modified;
	Time last_disk_mtime;

	PieceTable table;
	List{BytePos} line_starts;
	List{LineState} line_states;
	List{Cursor} cursors;
}

fn void Document.init(
	&self,
	Allocator allocator,
	String filepath = "untitled.c3",
	bool file_specified = false,
	char[] content = { },
	bool is_mmap = false,
	FileMmap mmap_handle = { },
	bool owns_buffer = true
)
{
	self.filepath = filepath.copy(allocator);
	self.is_file_specified = file_specified;
	self.is_modified = false;
	self.last_disk_mtime = (Time)0;

	self.table.init(allocator, content, is_mmap, mmap_handle, owns_buffer);
	self.line_starts.init(allocator, 32);
	self.line_states.init(allocator, 32);
	self.cursors.init(allocator, 8);
	self.cursors.push({ 0, 0, 0 });
}

fn void Document.free(&self, Allocator allocator)
{
	self.table.free();
	self.line_starts.free();
	self.line_states.free();
	self.cursors.free();
	if (self.filepath.len > 0)
	{
		alloc::free(allocator, self.filepath.ptr);
		self.filepath = "";
	}
	*self = { };
}

fn Cursor* Document.primary_cursor(&self)
{
	if (self.cursors.len() == 0)
	{
		self.cursors.push({ 0, 0, 0 });
	}
	return &self.cursors[0];
}

fn int Document.get_total_lines(&self)
{
	if (self.line_starts.len() == 0) return 1;
	return (int)self.line_starts.len();
}

fn BytePos Document.get_line_start_of_line(&self, int target_line)
{
	if (target_line <= 0 || self.line_starts.len() == 0) return 0;
	if (target_line >= (int)self.line_starts.len()) return self.table.len();
	return self.line_starts[(sz)target_line];
}

fn BytePos Document.get_line_start(&self, BytePos pos)
{
	int line = self.get_line(pos);
	return self.get_line_start_of_line(line);
}

fn BytePos Document.get_line_end(&self, BytePos pos)
{
	int line = self.get_line(pos);
	if (line + 1 < (int)self.line_starts.len())
	{
		return self.line_starts[(sz)(line + 1)] - 1;
	}
	return self.table.len();
}

fn int Document.get_line(&self, BytePos pos)
{
	sz len = self.line_starts.len();
	if (len <= 1 || pos == 0) return 0;
	BytePos total_len = self.table.len();
	if (pos > total_len) pos = total_len;

	sz low  = 0;
	sz high = len - 1;
	sz ans  = 0;
	while (low <= high)
	{
		sz mid = low + (high - low) / 2;
		if (self.line_starts[mid] <= pos)
		{
			ans = mid;
			low = mid + 1;
		}
		else
		{
			if (mid == 0) break;
			high = mid - 1;
		}
	}
	return (int)ans;
}

fn int Document.advance_col(&self, int col, char c) @inline
{
	if (c == '\t')
	{
		return col + (config::settings.tab_size - (col % config::settings.tab_size));
	}
	return col + 1;
}

fn int Document.get_col(&self, BytePos pos)
{
	BytePos total_len = self.table.len();
	if (pos > total_len) pos = total_len;

	BytePos line_start = self.get_line_start(pos);
	if (line_start > total_len) line_start = total_len;
	if (pos <= line_start) return 0;

	String line_slice = self.table.get_slice(line_start, pos, tmem);
	int col           = 0;
	sz p              = 0;

	while (p < line_slice.len)
	{
		char c = line_slice[p];
		switch (c)
		{
			case '\n':
				col = 0;
				p++;
			case '\r':
				p++;
			default:
				col = self.advance_col(col, c);
				sz char_len = 1;
				while (p + char_len < line_slice.len && (line_slice[p + char_len] & 0xC0) == 0x80) char_len++;
				p += char_len;
		}
	}
	return col;
}

fn LineCol Document.get_line_col(&self, BytePos pos) => { .line = self.get_line(pos), .col = self.get_col(pos) };

fn BytePos Document.get_pos_from_line_col(&self, int target_line, int target_col)
{
	BytePos line_start = self.get_line_start_of_line(target_line);
	BytePos line_end   = self.get_line_end(line_start);
	if (target_col <= 0 || line_start >= line_end) return line_start;

	String line_slice = self.table.get_slice(line_start, line_end, tmem);
	int col           = 0;
	sz p              = 0;

	while (p < line_slice.len && col < target_col)
	{
		char c = line_slice[p];
		switch (c)
		{
			case '\r':
				p++;
			default:
				col = self.advance_col(col, c);
				sz char_len = 1;
				while (p + char_len < line_slice.len && (line_slice[p + char_len] & 0xC0) == 0x80) char_len++;
				p += char_len;
		}
	}
	return line_start + (BytePos)p;
}

fn void Document.normalize_cursors(&self)
{
	if (self.cursors.len() == 0)
	{
		self.cursors.push({ 0, 0, 0 });
	}

	BytePos doc_len = self.table.len();
	foreach (&cur : self.cursors)
	{
		cur.pos = math::min(cur.pos, doc_len);
		cur.anchor = math::min(cur.anchor, doc_len);
		cur.target_col = self.get_col(cur.pos);
	}

	if (self.cursors.len() <= 1) return;

	sort::quicksort(&self.cursors, fn int (Cursor a, Cursor b) => compare_cursors(&a, &b));

	sz i = 0;
	while (i + 1 < self.cursors.len())
	{
		Cursor cur  = self.cursors[i];
		Cursor next = self.cursors[i + 1];

		bool cur_has_sel  = cur.has_selection();
		bool next_has_sel = next.has_selection();

		if (!cur_has_sel && !next_has_sel)
		{
			if (cur.pos == next.pos)
			{
				self.cursors.remove_at(i + 1);
				continue;
			}
		}
		else
		{
			BytePos cur_s  = cur.sel_start();
			BytePos cur_e  = cur.sel_end();
			BytePos next_s = next.sel_start();
			BytePos next_e = next.sel_end();

			if (next_s <= cur_e)
			{
				BytePos merged_s = math::min(cur_s, next_s);
				BytePos merged_e = math::max(cur_e, next_e);
				self.cursors[i].anchor = merged_s;
				self.cursors[i].pos = merged_e;
				self.cursors[i].target_col = self.get_col(merged_e);
				self.cursors.remove_at(i + 1);
				continue;
			}
		}
		i++;
	}
}

fn void Document.rebuild_line_index(&self) => @pool()
{
	if (self.line_starts.entries == null) self.line_starts.init(mem);
	self.line_starts.clear();
	self.line_starts.push(0);

	if (self.line_states.entries == null) self.line_states.init(mem);
	self.line_states.clear();

	BytePos piece_start_pos = 0;
	LineState current_state = LineState.NORMAL;

	foreach (&p : self.table.pieces)
	{
		char[] slice = (p.source == ORIGINAL) ? self.table.original_buffer[p.offset:p.length]
			: self.table.add_buffer[p.offset:p.length];

		sz line_start_idx = 0;
		for (sz i = 0; i < p.length; i++)
		{
			char c = slice[i];
			if (c == '\n')
			{
				String line_str = (String)slice[line_start_idx:i - line_start_idx];
				current_state = syntax::lex_state_only(line_str, current_state);
				self.line_states.push(current_state);

				self.line_starts.push(piece_start_pos + (BytePos)i + 1);
				line_start_idx = i + 1;
			}
		}

		if (line_start_idx < p.length)
		{
			String line_str = (String)slice[line_start_idx:p.length - line_start_idx];
			current_state = syntax::lex_state_only(line_str, current_state);
		}
		piece_start_pos += p.length;
	}

	self.line_states.push(current_state);
	self.normalize_cursors();
}

fn void Document.update_line_index_on_edit(
	&self,
	BytePos edit_start,
	BytePos deleted_len,
	BytePos inserted_len
) => @pool()
{
	BytePos total_len = self.table.len();
	if (edit_start > total_len) edit_start = total_len;

	int start_line   = self.get_line(edit_start);
	BytePos old_end  = edit_start + deleted_len;

	sz start_remove_idx = (sz)(start_line + 1);
	sz end_remove_idx   = start_remove_idx;

	while (end_remove_idx < self.line_starts.len() && self.line_starts[end_remove_idx] <= old_end)
	{
		end_remove_idx++;
	}

	sz remove_count = end_remove_idx - start_remove_idx;
	if (remove_count > 0)
	{
		sz remaining_starts = self.line_starts.len() - end_remove_idx;
		if (remaining_starts > 0)
		{
			mem::move(
				&self.line_starts.entries[start_remove_idx],
				&self.line_starts.entries[end_remove_idx],
				remaining_starts * BytePos::size
			);
		}
		self.line_starts.size -= remove_count;

		if (start_remove_idx < self.line_states.len())
		{
			sz states_end       = math::min(end_remove_idx, self.line_states.len());
			sz states_remove    = states_end - start_remove_idx;
			sz remaining_states = self.line_states.len() - states_end;
			if (remaining_states > 0)
			{
				mem::move(
					&self.line_states.entries[start_remove_idx],
					&self.line_states.entries[states_end],
					remaining_states * LineState::size
				);
			}
			self.line_states.size -= states_remove;
		}
	}

	BytePos insert_scan_end = edit_start + inserted_len;
	List{BytePos} new_line_starts;
	new_line_starts.tinit(16);

	for (BytePos p = edit_start; p < insert_scan_end; p++)
	{
		if (self.table.char_at(p) == '\n')
		{
			new_line_starts.push(p + 1);
		}
	}

	sz inserted_lines_count = new_line_starts.len();
	if (inserted_lines_count > 0)
	{
		sz insert_pos = (sz)(start_line + 1);
		sz old_total  = self.line_starts.len();

		self.line_starts.reserve(inserted_lines_count);
		self.line_starts.size += inserted_lines_count;

		sz to_shift = old_total - insert_pos;
		if (to_shift > 0)
		{
			mem::move(
				&self.line_starts.entries[insert_pos + inserted_lines_count],
				&self.line_starts.entries[insert_pos],
				to_shift * BytePos::size
			);
		}

		mem::copy(&self.line_starts.entries[insert_pos], new_line_starts.entries, inserted_lines_count * BytePos::size);

		self.line_states.reserve(inserted_lines_count);
		sz old_states_total = self.line_states.len();
		sz state_insert_pos = math::min(insert_pos - 1, old_states_total);
		self.line_states.size += inserted_lines_count;

		sz states_to_shift = old_states_total - state_insert_pos;
		if (states_to_shift > 0)
		{
			mem::move(
				&self.line_states.entries[state_insert_pos + inserted_lines_count],
				&self.line_states.entries[state_insert_pos],
				states_to_shift * LineState::size
			);
		}
		for (sz k = 0; k < inserted_lines_count; k++)
		{
			self.line_states.entries[state_insert_pos + k] = LineState.NORMAL;
		}
	}

	if (deleted_len != inserted_len)
	{
		sz subsequent_idx = (sz)(start_line + 1 + (int)inserted_lines_count);
		sz total_starts   = self.line_starts.len();
		if (inserted_len >= deleted_len)
		{
			BytePos diff = inserted_len - deleted_len;
			for (sz i = subsequent_idx; i < total_starts; i++)
			{
				self.line_starts.entries[i] += diff;
			}
		}
		else
		{
			BytePos diff = deleted_len - inserted_len;
			for (sz i = subsequent_idx; i < total_starts; i++)
			{
				self.line_starts.entries[i] -= diff;
			}
		}
	}

	int total_lines = (int)self.line_starts.len();
	while (self.line_states.len() < (sz)total_lines)
	{
		self.line_states.push(LineState.NORMAL);
	}

	int cur_line = start_line;
	while (cur_line < total_lines)
	{
		BytePos l_start = self.get_line_start_of_line(cur_line);
		BytePos l_end   = self.get_line_end(l_start);
		String line_str = self.table.get_slice(l_start, l_end, tmem);

		LineState prev_state = (cur_line == 0) ? LineState.NORMAL : self.line_states[(sz)(cur_line - 1)];
		LineState new_state  = syntax::lex_state_only(line_str, prev_state);

		LineState old_state = self.line_states[(sz)cur_line];
		self.line_states[(sz)cur_line] = new_state;

		if (new_state == old_state && cur_line >= start_line + (int)inserted_lines_count)
		{
			break;
		}
		cur_line++;
	}
}

fn void Document.apply_cursor_edit(
	&self,
	Cursor* cur,
	BytePos start,
	BytePos end,
	char[] replacement,
	sz* delta
)
{
	BytePos del_len = end - start;
	BytePos ins_len = replacement.len;

	if (del_len > 0)
	{
		self.table.replace_range(start, end, replacement);
	}
	else if (ins_len > 0)
	{
		self.table.insert_bytes(start, replacement);
	}

	self.update_line_index_on_edit(start, del_len, ins_len);

	cur.pos        = start + ins_len;
	cur.anchor     = cur.pos;
	cur.target_col = self.get_col(cur.pos);
	*delta         = ins_len - del_len;
}

macro void Document.@mutate_cursors(&self; @body(Cursor* cur, sz* delta))
{
	self.table.begin_transaction(&self.cursors);
	sort::quicksort(&self.cursors, fn int (Cursor a, Cursor b) => compare_cursors(&a, &b));

	for (sz k = self.cursors.len(); k > 0; k--)
	{
		sz i = k - 1;
		Cursor* cur = &self.cursors[i];
		sz delta = 0;
		@body(cur, &delta);

		if (delta != 0)
		{
			for (sz j = i + 1; j < self.cursors.len(); j++)
			{
				self.cursors[j].pos += delta;
				self.cursors[j].anchor += delta;
			}
		}
	}
	self.normalize_cursors();
	self.table.end_transaction(&self.cursors);
	self.is_modified = true;
}

macro void Document.@mutate_selected_lines(&self; @body(int line_idx, BytePos l_start, BytePos l_end))
{
	List{int} lines = self.get_selected_or_cursor_lines();
	if (lines.len() == 0) return;

	self.table.begin_transaction(&self.cursors);

	for (sz k = lines.len(); k > 0; k--)
	{
		int l = lines[k - 1];
		BytePos l_start = self.get_line_start_of_line(l);
		BytePos l_end   = self.get_line_end(l_start);
		@body(l, l_start, l_end);
	}

	foreach (&cur : self.cursors) cur.target_col = self.get_col(cur.pos);
	self.normalize_cursors();
	self.table.end_transaction(&self.cursors);
	self.is_modified = true;
}

fn void Document.shift_cursors_after_edit(&self, BytePos edit_pos, BytePos del_len, BytePos ins_len)
{
	if (del_len > 0)
	{
		BytePos del_end = edit_pos + del_len;
		foreach (&cur : self.cursors)
		{
			if (cur.pos >= del_end)
			{
				cur.pos -= del_len;
			}
			else if (cur.pos >= edit_pos)
			{
				cur.pos = edit_pos;
			}

			if (cur.anchor >= del_end)
			{
				cur.anchor -= del_len;
			}
			else if (cur.anchor >= edit_pos)
			{
				cur.anchor = edit_pos;
			}
		}
	}
	if (ins_len > 0)
	{
		foreach (&cur : self.cursors)
		{
			if (cur.pos >= edit_pos) cur.pos += ins_len;
			if (cur.anchor >= edit_pos) cur.anchor += ins_len;
		}
	}
}

fn List{int} Document.get_selected_or_cursor_lines(&self)
{
	List{int} lines;
	lines.tinit(self.cursors.len() * 4);

	foreach (&cur : self.cursors)
	{
		int s_line = self.get_line(cur.sel_start());
		int e_line = self.get_line(cur.sel_end());
		if (cur.has_selection() && e_line > s_line && cur.sel_end() == self.get_line_start_of_line(e_line))
		{
			e_line--;
		}
		for (int l = s_line; l <= e_line; l++)
		{
			if (!lines.contains(l)) lines.push(l);
		}
	}

	sort::quicksort(&lines, fn int (int a, int b) => (a < b) ? -1 : ((a > b) ? 1 : 0));
	return lines;
}

fn void Document.insert_codepoint(&self, Char32 c)
{
	if (c == '\n')
	{
		self.handle_enter();
		return;
	}

	char close_pair = '\0';
	if (config::settings.auto_close_brackets)
	{
		switch (c)
		{
			case '(': close_pair = ')';
			case '[': close_pair = ']';
			case '{': close_pair = '}';
			case '"': close_pair = '"';
			case '\'': close_pair = '\'';
			default: break;
		}
	}

	char[4] buf;
	sz len = conv::char32_to_utf8(c, &buf) ?? 0;
	if (len == 0) return;

	self.@mutate_cursors(; cur, delta)
	{
		if (!cur.has_selection() && cur.pos < self.table.len())
		{
			char next_c = self.table.char_at(cur.pos);
			if ((c == ')' && next_c == ')') || (c == ']' && next_c == ']') || (c == '}' && next_c == '}')
				|| (c == '"' && next_c == '"')
				|| (c == '\'' && next_c == '\''))
			{
				cur.pos = get_next_char_pos(&self.table, cur.pos);
				cur.anchor = cur.pos;
				cur.target_col = self.get_col(cur.pos);
				return;
			}
		}

		BytePos start_sel = cur.sel_start();
		BytePos end_sel   = cur.sel_end();

		if (close_pair != '\0')
		{
			char[2] pair_buf = { (char)c, close_pair };
			self.apply_cursor_edit(cur, start_sel, end_sel, pair_buf[:2], delta);
			cur.pos = start_sel + 1;
			cur.anchor = cur.pos;
		}
		else
		{
			self.apply_cursor_edit(cur, start_sel, end_sel, buf[:len], delta);
		}
		cur.target_col = self.get_col(cur.pos);
	};
}

fn void Document.handle_enter(&self)
{
	self.@mutate_cursors(; cur, delta)
	{
		BytePos start_sel = cur.sel_start();
		BytePos end_sel   = cur.sel_end();

		BytePos line_start = self.get_line_start(start_sel);
		BytePos pos        = line_start;
		DString indent;
		indent.tinit();

		while (pos < start_sel)
		{
			char ch = self.table.char_at(pos);
			if (ch == ' ' || ch == '\t')
			{
				indent.append_char(ch);
				pos++;
			}
			else
			{
				break;
			}
		}

		bool between_braces = false;
		if (start_sel > 0 && end_sel < self.table.len())
		{
			char prev_c = self.table.char_at(get_prev_char_pos(&self.table, start_sel));
			char next_c = self.table.char_at(end_sel);
			if (prev_c == '{' && next_c == '}') between_braces = true;
		}

		if (between_braces)
		{
			DString ins;
			ins.tinit();
			ins.append_char('\n');
			ins.append(indent.str_view());
			ins.append_char('\t');

			BytePos target_cursor = start_sel + ins.str_view().len;

			ins.append_char('\n');
			ins.append(indent.str_view());

			String ins_str = ins.str_view();
			self.apply_cursor_edit(cur, start_sel, end_sel, (char[])ins_str, delta);

			cur.pos = target_cursor;
			cur.anchor = cur.pos;
			cur.target_col = self.get_col(cur.pos);
			return;
		}

		if (start_sel > 0)
		{
			char last_c = self.table.char_at(get_prev_char_pos(&self.table, start_sel));
			if (last_c == '{' || last_c == ':')
			{
				indent.append_char('\t');
			}
		}

		DString ins;
		ins.tinit();
		ins.append_char('\n');
		ins.append(indent.str_view());

		String ins_str = ins.str_view();
		self.apply_cursor_edit(cur, start_sel, end_sel, (char[])ins_str, delta);
	};
}

fn void Document.handle_backspace(&self)
{
	self.@mutate_cursors(; cur, delta)
	{
		switch
		{
			case cur.has_selection():
				self.apply_cursor_edit(cur, cur.sel_start(), cur.sel_end(), { }, delta);
			case cur.pos > 0:
				BytePos prev = get_prev_char_pos(&self.table, cur.pos);
				self.apply_cursor_edit(cur, prev, cur.pos, { }, delta);
		}
	};
}

fn void Document.handle_delete(&self)
{
	self.@mutate_cursors(; cur, delta)
	{
		switch
		{
			case cur.has_selection():
				self.apply_cursor_edit(cur, cur.sel_start(), cur.sel_end(), { }, delta);
			case cur.pos < self.table.len():
				BytePos next = get_next_char_pos(&self.table, cur.pos);
				self.apply_cursor_edit(cur, cur.pos, next, { }, delta);
		}
	};
}

fn void Document.delete_word_left(&self)
{
	self.@mutate_cursors(; cur, delta)
	{
		BytePos s = cur.has_selection() ? cur.sel_start() : get_prev_word_pos(&self.table, cur.pos);
		BytePos e = cur.has_selection() ? cur.sel_end() : cur.pos;
		if (e > s) self.apply_cursor_edit(cur, s, e, { }, delta);
	};
}

fn void Document.delete_word_right(&self)
{
	self.@mutate_cursors(; cur, delta)
	{
		BytePos s = cur.has_selection() ? cur.sel_start() : cur.pos;
		BytePos e = cur.has_selection() ? cur.sel_end() : get_next_word_pos(&self.table, cur.pos);
		if (e > s) self.apply_cursor_edit(cur, s, e, { }, delta);
	};
}

fn void Document.delete_selection(&self)
{
	self.@mutate_cursors(; cur, delta)
	{
		if (cur.has_selection())
		{
			self.apply_cursor_edit(cur, cur.sel_start(), cur.sel_end(), { }, delta);
		}
	};
}

fn void Document.indent_block(&self, bool outdent)
{
	self.@mutate_selected_lines(; l, l_start, l_end)
	{
		if (outdent)
		{
			if (l_start < l_end)
			{
				char ch    = self.table.char_at(l_start);
				sz del_len = 0;
				switch (ch)
				{
					case '\t':
						del_len = 1;
					case ' ':
						BytePos p = l_start;
						while (p < l_end && del_len < (sz)config::settings.tab_size && self.table.char_at(p) == ' ')
						{
							del_len++;
							p++;
						}
					default: break;
				}

				if (del_len > 0)
				{
					self.table.delete_range(l_start, l_start + del_len);
					self.update_line_index_on_edit(l_start, del_len, 0);
					self.shift_cursors_after_edit(l_start, del_len, 0);
				}
			}
		}
		else
		{
			self.table.insert_bytes(l_start, (char[])"\t");
			self.update_line_index_on_edit(l_start, 0, 1);
			self.shift_cursors_after_edit(l_start, 0, 1);
		}
	};
}

fn void Document.toggle_comment(&self)
{
	List{int} lines = self.get_selected_or_cursor_lines();
	if (lines.len() == 0) return;

	bool all_commented = true;
	foreach (l : lines)
	{
		BytePos l_start = self.get_line_start_of_line(l);
		BytePos l_end   = self.get_line_end(l_start);
		if (l_end <= l_start) continue;

		BytePos p = l_start;
		while (p < l_end && (self.table.char_at(p) == ' ' || self.table.char_at(p) == '\t')) p++;

		if (p + 1 >= l_end || self.table.char_at(p) != '/' || self.table.char_at(p + 1) != '/')
		{
			all_commented = false;
			break;
		}
	}

	self.@mutate_selected_lines(; l, l_start, l_end)
	{
		BytePos p = l_start;
		while (p < l_end && (self.table.char_at(p) == ' ' || self.table.char_at(p) == '\t')) p++;

		if (all_commented)
		{
			if (p + 1 < l_end && self.table.char_at(p) == '/' && self.table.char_at(p + 1) == '/')
			{
				BytePos del_len = (p + 2 < l_end && self.table.char_at(p + 2) == ' ') ? 3 : 2;
				self.table.delete_range(p, p + del_len);
				self.update_line_index_on_edit(p, del_len, 0);
				self.shift_cursors_after_edit(p, del_len, 0);
			}
		}
		else
		{
			self.table.insert_bytes(p, (char[])"// ");
			self.update_line_index_on_edit(p, 0, 3);
			self.shift_cursors_after_edit(p, 0, 3);
		}
	};
}

fn void Document.duplicate_line(&self)
{
	List{int} lines = self.get_selected_or_cursor_lines();
	if (lines.len() == 0) return;

	self.table.begin_transaction(&self.cursors);

	int first_line = lines[0];
	int last_line  = lines[lines.len() - 1];

	BytePos block_start = self.get_line_start_of_line(first_line);
	BytePos block_end   = self.get_line_end(self.get_line_start_of_line(last_line));

	DString block_str;
	block_str.tinit();
	block_str.append_char('\n');
	self.table.append_range_to_dstring(&block_str, block_start, block_end);

	String text = block_str.str_view();
	self.table.insert_bytes(block_end, (char[])text);
	self.update_line_index_on_edit(block_end, 0, text.len);

	sz shift_delta = text.len;
	foreach (&cur : self.cursors)
	{
		cur.pos += shift_delta;
		cur.anchor += shift_delta;
		cur.target_col = self.get_col(cur.pos);
	}

	self.normalize_cursors();
	self.table.end_transaction(&self.cursors);
	self.is_modified = true;
}

fn void Document.delete_line(&self)
{
	self.@mutate_selected_lines(; l, l_start, l_end)
	{
		BytePos del_start = l_start;
		BytePos del_end   = l_end;

		if (del_end < self.table.len())
		{
			if (self.table.char_at(del_end) == '\r' && self.table.char_at(del_end + 1) == '\n')
			{
				del_end += 2;
			}
			else if (self.table.char_at(del_end) == '\n' || self.table.char_at(del_end) == '\r')
			{
				del_end += 1;
			}
		}
		else if (del_start > 0)
		{
			if (self.table.char_at(del_start - 1) == '\n')
			{
				del_start--;
				if (del_start > 0 && self.table.char_at(del_start - 1) == '\r')
				{
					del_start--;
				}
			}
		}

		BytePos del_len = del_end - del_start;
		if (del_len > 0)
		{
			self.table.delete_range(del_start, del_end);
			self.update_line_index_on_edit(del_start, del_len, 0);
			self.shift_cursors_after_edit(del_start, del_len, 0);
		}
	};
}

fn void Document.move_lines_vertical(&self, bool move_up)
{
	List{int} lines = self.get_selected_or_cursor_lines();
	if (lines.len() == 0) return;

	int first_l = lines[0];
	int last_l  = lines[lines.len() - 1];
	int tot     = self.get_total_lines();

	if (move_up && first_l == 0) return;
	if (!move_up && last_l >= tot - 1) return;

	self.table.begin_transaction(&self.cursors);

	if (move_up)
	{
		int target_l = first_l - 1;
		BytePos target_start = self.get_line_start_of_line(target_l);
		BytePos target_end   = self.get_line_end(target_start);

		BytePos block_start  = self.get_line_start_of_line(first_l);
		BytePos block_end    = self.get_line_end(self.get_line_start_of_line(lines[lines.len() - 1]));

		String target_str = self.table.get_slice(target_start, target_end, tmem);
		String block_str  = self.table.get_slice(block_start, block_end, tmem);

		DString combined;
		combined.tinit();
		combined.append(block_str);
		combined.append_char('\n');
		combined.append(target_str);

		String s = combined.str_view();
		BytePos total_span = block_end - target_start;
		self.table.replace_range(target_start, block_end, (char[])s);
		self.update_line_index_on_edit(target_start, total_span, s.len);

		sz shift = target_str.len + 1;
		foreach (&cur : self.cursors)
		{
			cur.pos -= shift;
			cur.anchor -= shift;
			cur.target_col = self.get_col(cur.pos);
		}
	}
	else
	{
		int target_l = last_l + 1;
		BytePos block_start  = self.get_line_start_of_line(first_l);
		BytePos block_end    = self.get_line_end(self.get_line_start_of_line(last_l));

		BytePos target_start = self.get_line_start_of_line(target_l);
		BytePos target_end   = self.get_line_end(target_start);

		String block_str  = self.table.get_slice(block_start, block_end, tmem);
		String target_str = self.table.get_slice(target_start, target_end, tmem);

		DString combined;
		combined.tinit();
		combined.append(target_str);
		combined.append_char('\n');
		combined.append(block_str);

		String s = combined.str_view();
		BytePos total_span = target_end - block_start;
		self.table.replace_range(block_start, target_end, (char[])s);
		self.update_line_index_on_edit(block_start, total_span, s.len);

		sz shift = target_str.len + 1;
		foreach (&cur : self.cursors)
		{
			cur.pos += shift;
			cur.anchor += shift;
			cur.target_col = self.get_col(cur.pos);
		}
	}

	self.normalize_cursors();
	self.table.end_transaction(&self.cursors);
	self.is_modified = true;
}

fn void Document.convert_case_selection(&self, bool to_upper)
{
	self.table.begin_transaction(&self.cursors);
	sort::quicksort(&self.cursors, fn int (Cursor a, Cursor b) => compare_cursors(&a, &b));

	for (sz k = self.cursors.len(); k > 0; k--)
	{
		sz i = k - 1;
		Cursor* cur = &self.cursors[i];
		if (cur.has_selection())
		{
			BytePos start = cur.sel_start();
			BytePos end   = cur.sel_end();

			String text = self.table.get_slice(start, end, tmem);
			String modified = to_upper ? text.to_upper_tcopy() : text.to_lower_tcopy();

			self.table.replace_range(start, end, (char[])modified);
			self.update_line_index_on_edit(start, end - start, modified.len);

			if (cur.pos >= cur.anchor)
			{
				cur.anchor = start;
				cur.pos    = start + modified.len;
			}
			else
			{
				cur.pos    = start;
				cur.anchor = start + modified.len;
			}
			cur.target_col = self.get_col(cur.pos);
		}
	}
	self.normalize_cursors();
	self.table.end_transaction(&self.cursors);
	self.is_modified = true;
}

fn void Document.jump_to_matching_bracket(&self, bool select)
{
	if (self.table.len() == 0) return;
	Cursor* cur = self.primary_cursor();
	BytePos p   = cur.pos;
	if (p >= self.table.len()) p = self.table.len() - 1;

	char c          = self.table.char_at(p);
	char match_char = '\0';
	bool forward    = true;

	switch (c)
	{
		case '(': match_char = ')'; forward = true;
		case '[': match_char = ']'; forward = true;
		case '{': match_char = '}'; forward = true;
		case ')': match_char = '('; forward = false;
		case ']': match_char = '['; forward = false;
		case '}': match_char = '{'; forward = false;
		default:
			if (p > 0)
			{
				p = get_prev_char_pos(&self.table, p);
				c = self.table.char_at(p);
				switch (c)
				{
					case '(': match_char = ')'; forward = true;
					case '[': match_char = ']'; forward = true;
					case '{': match_char = '}'; forward = true;
					case ')': match_char = '('; forward = false;
					case ']': match_char = '['; forward = false;
					case '}': match_char = '{'; forward = false;
					default: break;
				}
			}
	}

	if (match_char == '\0') return;

	int depth     = 1;
	BytePos total = self.table.len();

	if (forward)
	{
		for (BytePos i = p + 1; i < total; i = get_next_char_pos(&self.table, i))
		{
			char ch = self.table.char_at(i);
			switch
			{
				case ch == c: depth++;
				case ch == match_char:
					depth--;
					if (depth == 0)
					{
						cur.pos = i;
						if (!select) cur.anchor = cur.pos;
						cur.target_col = self.get_col(cur.pos);
						return;
					}
			}
		}
	}
	else
	{
		BytePos i = p;
		while (i > 0)
		{
			i = get_prev_char_pos(&self.table, i);
			char ch = self.table.char_at(i);
			switch
			{
				case ch == c: depth++;
				case ch == match_char:
					depth--;
					if (depth == 0)
					{
						cur.pos = i;
						if (!select) cur.anchor = cur.pos;
						cur.target_col = self.get_col(cur.pos);
						return;
					}
			}
		}
	}
}

fn void Document.add_cursor_vertical(&self, bool above)
{
	foreach (&cur : self.cursors)
	{
		if (cur.has_selection()) return;
	}

	List{Cursor} new_list;
	new_list.tinit(self.cursors.len() * 2);
	int tot = self.get_total_lines();

	foreach (&cur : self.cursors)
	{
		new_list.push(*cur);
		int line = self.get_line(cur.pos);
		int target_l = above ? (line - 1) : (line + 1);
		if (target_l >= 0 && target_l < tot)
		{
			BytePos new_p = self.get_pos_from_line_col(target_l, cur.target_col);
			new_list.push({ new_p, new_p, cur.target_col });
		}
	}
	self.cursors.clear();
	foreach (&cur : new_list) self.cursors.push(*cur);
	self.normalize_cursors();
}

fn void Document.add_next_occurrence(&self, Tab* tab, int visible_lines, int visible_cols) => @pool()
{
	Cursor* prim = self.primary_cursor();

	if (!prim.has_selection())
	{
		TextRange bounds = get_word_bounds(&self.table, prim.pos);
		if (bounds.start < bounds.end)
		{
			prim.anchor = bounds.start;
			prim.pos = bounds.end;
			prim.target_col = self.get_col(prim.pos);
			tab.ensure_pos_visible(prim.pos, visible_lines, visible_cols);
			return;
		}
	}

	String query = self.table.get_slice(prim.sel_start(), prim.sel_end(), tmem);
	if (query.len == 0) return;
	sz qlen = query.len;
	if (self.table.len() < qlen) return;

	BytePos max_end = 0;
	foreach (&c : self.cursors)
	{
		max_end = math::max(max_end, c.sel_end());
	}

	if (max_end + qlen <= self.table.len())
	{
		if (try next_idx = self.table.find_forward(max_end, query, true))
		{
			BytePos n_start = next_idx;
			BytePos n_end = n_start + qlen;
			self.cursors.push({ .pos = n_end, .anchor = n_start, .target_col = self.get_col(n_end) });
			self.normalize_cursors();
			tab.ensure_pos_visible(n_end, visible_lines, visible_cols);
			return;
		}
	}

	BytePos scan_pos = 0;
	while (scan_pos + qlen <= self.table.len())
	{
		if (try idx = self.table.find_forward(scan_pos, query, true))
		{
			BytePos match_start = idx;
			BytePos match_end = match_start + qlen;

			bool already_selected = false;
			foreach (&c : self.cursors)
			{
				if (c.sel_start() == match_start && c.sel_end() == match_end)
				{
					already_selected = true;
					break;
				}
			}

			if (!already_selected)
			{
				self.cursors.push({ .pos = match_end, .anchor = match_start, .target_col = self.get_col(match_end) });
				self.normalize_cursors();
				tab.ensure_pos_visible(match_end, visible_lines, visible_cols);
				return;
			}
			scan_pos = match_start + 1;
		}
		else
		{
			break;
		}
	}
}

fn void Document.undo(&self)
{
	BytePos edit_start;
	BytePos del_len;
	BytePos ins_len;
	if (self.table.undo_with_range(&self.cursors, &edit_start, &del_len, &ins_len))
	{
		self.rebuild_line_index();
		self.normalize_cursors();
		self.is_modified = true;
	}
}

fn void Document.redo(&self)
{
	BytePos edit_start;
	BytePos del_len;
	BytePos ins_len;
	if (self.table.redo_with_range(&self.cursors, &edit_start, &del_len, &ins_len))
	{
		self.rebuild_line_index();
		self.normalize_cursors();
		self.is_modified = true;
	}
}

struct Tab
{
	Document doc;
	int scroll_line;
	int scroll_col;
}

fn void Tab.init(
	&self,
	Allocator allocator,
	String filepath = "untitled.c3",
	bool file_specified = false,
	char[] content = { },
	bool is_mmap = false,
	FileMmap mmap_handle = { },
	bool owns_buffer = true
)
{
	self.doc.init(allocator, filepath, file_specified, content, is_mmap, mmap_handle, owns_buffer);
	self.scroll_line = 0;
	self.scroll_col = 0;
}

fn void Tab.free(&self, Allocator allocator)
{
	self.doc.free(allocator);
	*self = { };
}

fn void Tab.ensure_pos_visible(&self, BytePos pos, int visible_lines, int visible_cols)
{
	int cursor_line  = self.doc.get_line(pos);
	switch
	{
		case cursor_line < self.scroll_line:
			self.scroll_line = cursor_line;
		case cursor_line >= self.scroll_line + visible_lines:
			self.scroll_line = cursor_line - visible_lines + 1;
	}
	self.scroll_line = math::clamp(self.scroll_line, 0, math::max(0, self.doc.get_total_lines() - 1));

	int cursor_col = self.doc.get_col(pos);
	switch
	{
		case cursor_col < self.scroll_col:
			self.scroll_col = cursor_col;
		case cursor_col >= self.scroll_col + visible_cols:
			self.scroll_col = cursor_col - visible_cols + 1;
	}
	if (self.scroll_col < 0) self.scroll_col = 0;
}

fn void Tab.ensure_cursor_visible(&self, int visible_lines, int visible_cols)
{
	self.ensure_pos_visible(self.doc.primary_cursor().pos, visible_lines, visible_cols);
}
