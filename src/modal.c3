module c3ed;
import std;

enum ModalKind : int
{
	NONE,
	FIND,
	REPLACE,
	GLOBAL_GREP,
	QUICK_OPEN,
	GOTO_LINE,
	SYMBOL_OUTLINE,
	SAVE_AS,
	CONFIRM_EXIT,
	CONFIRM_CLOSE_TAB,
	CONFIRM_DISK_RELOAD
}

struct PickerItem
{
	String label;
	String detail;
	String target_path;
	int line;
	int col;
}

fn void PickerItem.free(&self, Allocator allocator = mem)
{
	if (self.label.len > 0) alloc::free(allocator, self.label.ptr);
	if (self.detail.len > 0) alloc::free(allocator, self.detail.ptr);
	if (self.target_path.len > 0) alloc::free(allocator, self.target_path.ptr);
	*self = { };
}

struct ScoredPickerItem @local
{
	PickerItem item;
	int score;
}

struct ModalState
{
	ModalKind kind;
	TextInputWidget input;
	TextInputWidget replace_input;
	int focus_field;

	bool search_case_sensitive;
	int cached_match_count;
	List{int} cached_match_lines;

	ListPickerWidget{PickerItem} picker;

	float grep_debounce_timer;
	bool grep_dirty;
}

fn void ModalState.init(&self, Allocator allocator = mem)
{
	self.kind = NONE;
	self.focus_field = 0;
	self.search_case_sensitive = false;
	self.cached_match_count = 0;
	self.cached_match_lines.init(allocator, 64);
	self.picker.init(allocator, 10);
	self.grep_debounce_timer = 0.0f;
	self.grep_dirty = false;
}

fn void ModalState.free(&self)
{
	self.cached_match_lines.free();
	foreach (&item : self.picker.items) item.free(mem);
	self.picker.items.free();
	*self = { };
}

fn void ModalState.close(&self)
{
	self.kind = NONE;
}

fn bool fuzzy_match(String text, String pattern)
{
	StringIterator pat_it = pattern.iterator();
	Char32 pc @noinit;

	if (try first_pc = pat_it.next())
	{
		pc = first_pc;
	}
	else
	{
		return true;
	}

	StringIterator text_it = text.iterator();
	while (try tc = text_it.next())
	{
		if (tc <= 0x7F && pc <= 0x7F ? ((char)tc).to_lower() == ((char)pc).to_lower() : tc == pc)
		{
			if (try next_pc = pat_it.next())
			{
				pc = next_pc;
			}
			else
			{
				return true;
			}
		}
	}
	return false;
}

fn int score_quick_open_match(String filepath, String query)
{
	if (query.len == 0) return 1;

	String q    = query.to_lower_tcopy();
	String fp   = filepath.to_lower_tcopy();
	String base = (filepath.file_tbasename() ?? filepath).to_lower_tcopy();

	if (!q.contains_char(' '))
	{
		int score = 0;
		switch
		{
			case base == q:           score += 10000;
			case fp == q:             score += 9000;
			case base.starts_with(q): score += 6000;
			case base.contains(q):    score += 4000;
			case fp.starts_with(q):   score += 2500;
			case fp.contains(q):      score += 1500;
			case fuzzy_match(base, q): score += 800;
			case fuzzy_match(fp, q):  score += 200;
			default: return 0;
		}
		if (try dot_idx = base.rindex_of_char('.'))
		{
			if (base[:dot_idx] == q) score += 3000;
		}
		score += math::max(0, 100 - (int)filepath.len);
		return score;
	}

	Splitter tokens = q.tokenize(" ");
	int token_count = 0;
	int score       = 0;

	while (try token = tokens.next())
	{
		if (token.len == 0) continue;
		token_count++;
		switch
		{
			case base == token:           score += 3000;
			case base.starts_with(token): score += 1500;
			case base.contains(token):    score += 1000;
			case fp.contains(token):      score += 500;
			case fuzzy_match(base, token): score += 200;
			case fuzzy_match(fp, token):  score += 50;
			default: return 0;
		}
	}
	if (token_count == 0) return 1;
	score += math::max(0, 100 - (int)filepath.len);
	return score;
}

fn int score_grep_match(String line, String query)
{
	if (query.len == 0) return 1;
	String line_lower  = line.to_lower_tcopy();
	String query_lower = query.to_lower_tcopy();

	if (line_lower.contains(query_lower)) return 1000;
	if (!query_lower.contains_char(' '))
	{
		return fuzzy_match(line_lower, query_lower) ? 200 : 0;
	}

	Splitter tokens = query_lower.tokenize(" ");
	int score       = 0;
	while (try token = tokens.next())
	{
		if (token.len == 0) continue;
		switch
		{
			case line_lower.contains(token): score += 300;
			case fuzzy_match(line_lower, token): score += 50;
			default: return 0;
		}
	}
	return score;
}

fn void ModalState.update_cached_search_matches(&self, Document* doc) => @pool()
{
	self.cached_match_lines.clear();

	if ((self.kind != FIND && self.kind != REPLACE) || self.input.length == 0)
	{
		self.cached_match_count = 0;
		return;
	}

	String query = self.input.view();
	sz qlen      = query.len;
	if (doc.table.len() < qlen) return;

	BytePos sp = 0;
	int match_count = 0;

	while (sp + qlen <= doc.table.len())
	{
		if (try idx = doc.table.find_forward(sp, query, self.search_case_sensitive))
		{
			match_count++;
			if (self.cached_match_lines.len() < 30000)
			{
				int line_idx = doc.get_line(idx);
				self.cached_match_lines.push(line_idx);
			}
			sp = idx + qlen;
		}
		else
		{
			break;
		}
	}
	self.cached_match_count = match_count;
}

fn void ModalState.find_next(
	&self,
	Document* doc,
	bool reverse,
	Tab* tab,
	int visible_lines,
	int visible_cols
)
{
	String query = self.input.view();
	if (query.len == 0) return;
	sz qlen = query.len;
	if (doc.table.len() < qlen) return;

	Cursor* cur = doc.primary_cursor();

	if (!reverse)
	{
		BytePos search_start = cur.sel_end();
		if (search_start + qlen > doc.table.len()) search_start = 0;

		if (try idx = doc.table.find_forward(search_start, query, self.search_case_sensitive))
		{
			cur.anchor = idx;
			cur.pos = idx + qlen;
			cur.target_col = doc.get_col(cur.pos);
			tab.ensure_cursor_visible(visible_lines, visible_cols);
			return;
		}
		if (search_start > 0)
		{
			if (try idx = doc.table.find_forward(0, query, self.search_case_sensitive))
			{
				cur.anchor = idx;
				cur.pos = idx + qlen;
				cur.target_col = doc.get_col(cur.pos);
				tab.ensure_cursor_visible(visible_lines, visible_cols);
			}
		}
	}
	else
	{
		BytePos search_end = (cur.sel_start() > 0)
			? cur.sel_start() - 1
			: (doc.table.len() >= qlen ? doc.table.len() - qlen : 0);

		if (try idx = doc.table.find_backward(search_end, query, self.search_case_sensitive))
		{
			cur.anchor = idx;
			cur.pos = idx + qlen;
			cur.target_col = doc.get_col(cur.pos);
			tab.ensure_cursor_visible(visible_lines, visible_cols);
			return;
		}
		if (search_end < doc.table.len() - qlen)
		{
			if (try idx = doc.table.find_backward(doc.table.len() - qlen, query, self.search_case_sensitive))
			{
				cur.anchor = idx;
				cur.pos = idx + qlen;
				cur.target_col = doc.get_col(cur.pos);
				tab.ensure_cursor_visible(visible_lines, visible_cols);
			}
		}
	}
}

fn void ModalState.find_from_current(&self, Document* doc, Tab* tab, int visible_lines, int visible_cols)
{
	String query = self.input.view();
	if (query.len == 0) return;
	sz qlen = query.len;
	if (doc.table.len() < qlen) return;

	Cursor* cur          = doc.primary_cursor();
	BytePos search_start = cur.sel_start();
	if (search_start + qlen > doc.table.len()) search_start = 0;

	if (try idx = doc.table.find_forward(search_start, query, self.search_case_sensitive))
	{
		cur.anchor = idx;
		cur.pos = idx + qlen;
		cur.target_col = doc.get_col(cur.pos);
		tab.ensure_cursor_visible(visible_lines, visible_cols);
		return;
	}
	if (try idx = doc.table.find_forward(0, query, self.search_case_sensitive))
	{
		cur.anchor = idx;
		cur.pos = idx + qlen;
		cur.target_col = doc.get_col(cur.pos);
		tab.ensure_cursor_visible(visible_lines, visible_cols);
	}
}

fn void ModalState.replace_next(&self, Document* doc, Tab* tab, int visible_lines, int visible_cols)
{
	String query = self.input.view();
	if (query.len == 0) return;
	String replace_text = self.replace_input.view();

	Cursor* cur       = doc.primary_cursor();
	BytePos sel_start = cur.sel_start();
	BytePos sel_end   = cur.sel_end();

	bool is_matching = false;
	if (sel_end - sel_start == query.len)
	{
		DString cur_sel;
		cur_sel.tinit();
		doc.table.append_range_to_dstring(&cur_sel, sel_start, sel_end);
		String sel_view = cur_sel.str_view();
		is_matching = self.search_case_sensitive
			? (sel_view == query)
			: (sel_view.to_lower_tcopy() == query.to_lower_tcopy());
	}

	if (is_matching)
	{
		doc.table.begin_transaction(&doc.cursors);
		doc.table.replace_range(sel_start, sel_end, (char[])replace_text);
		doc.update_line_index_on_edit(sel_start, sel_end - sel_start, replace_text.len);

		cur.pos = sel_start + replace_text.len;
		cur.anchor = cur.pos;
		cur.target_col = doc.get_col(cur.pos);
		doc.table.end_transaction(&doc.cursors);
		doc.is_modified = true;
	}

	self.find_next(doc, false, tab, visible_lines, visible_cols);
	self.update_cached_search_matches(doc);
}

fn void ModalState.replace_all(&self, Document* doc, Tab* tab, int visible_lines, int visible_cols) => @pool()
{
	String query = self.input.view();
	if (query.len == 0) return;
	String replace_text = self.replace_input.view();

	sz qlen = query.len;
	if (doc.table.len() < qlen) return;

	List{BytePos} matches;
	matches.tinit(64);

	BytePos pos = 0;
	while (pos + qlen <= doc.table.len())
	{
		if (try idx = doc.table.find_forward(pos, query, self.search_case_sensitive))
		{
			matches.push(idx);
			pos = idx + qlen;
		}
		else
		{
			break;
		}
	}

	if (matches.len() == 0) return;

	String buf_str = doc.table.to_tstring();
	DString out_buf;
	out_buf.tinit(buf_str.len + matches.len() * replace_text.len + 64);

	BytePos last_pos = 0;
	foreach (m_pos : matches)
	{
		if (m_pos > last_pos)
		{
			out_buf.append(buf_str[last_pos:m_pos - last_pos]);
		}
		out_buf.append(replace_text);
		last_pos = m_pos + qlen;
	}
	if (last_pos < buf_str.len)
	{
		out_buf.append(buf_str[last_pos..]);
	}

	String new_doc    = out_buf.str_view();
	BytePos total_len = doc.table.len();

	doc.table.begin_transaction(&doc.cursors);
	doc.table.replace_range(0, total_len, (char[])new_doc);
	doc.rebuild_line_index();

	Cursor* cur = doc.primary_cursor();
	cur.pos = math::min(cur.pos, doc.table.len());
	cur.anchor = cur.pos;
	cur.target_col = doc.get_col(cur.pos);
	doc.table.end_transaction(&doc.cursors);

	doc.is_modified = true;
	self.update_cached_search_matches(doc);
	tab.ensure_cursor_visible(visible_lines, visible_cols);
}

fn void ModalState.clear_picker(&self)
{
	foreach (&item : self.picker.items) item.free(mem);
	self.picker.items.clear();
	self.picker.selected_index = 0;
	self.picker.scroll_offset = 0;
}

fn void ModalState.update_quick_open_results(&self, Workspace* ws) => @pool()
{
	self.clear_picker();
	String query = self.input.view().trim();

	bool has_slash = query.contains_char('/') || query.contains_char('\\');
	bool is_special_start = query.starts_with("~") || query.starts_with(".") || query.starts_with("/");

	if (has_slash || is_special_start)
	{
		String dir_part = "";
		String filter_part = "";

		sz? slash_pos = query.rindex_of_char('/') ?? query.rindex_of_char('\\');
		if (try s_idx = slash_pos)
		{
			if (s_idx == 0 && (query.starts_with("/") || query.starts_with("\\")))
			{
				dir_part = "/";
				filter_part = query[1..];
			}
			else
			{
				dir_part = query[:s_idx];
				filter_part = query[s_idx + 1..];
			}
		}
		else
		{
			dir_part = query;
			filter_part = "";
		}

		String resolved_dir = resolve_path_string(dir_part, tmem);
		if (resolved_dir.len > 0 && path::is_dir((Path)resolved_dir))
		{
			PathList? entries_opt = path::ls(tmem, (Path)resolved_dir, no_dirs: false, no_symlinks: true, relative: true);
			if (try entries = entries_opt)
			{
				List{ScoredPickerItem} candidates;
				candidates.tinit(entries.len());

				String filter_lower = filter_part.to_lower_tcopy();

				foreach (entry : entries)
				{
					String entry_str = (String)entry;
					if (entry_str.len == 0 || entry_str == "." || entry_str == "..") continue;
					if (is_ignored_dirname(entry_str)) continue;

					String full_rel;
					if (dir_part == "/" || dir_part == "\\")
					{
						full_rel = string::tformat("/%s", entry_str);
					}
					else if (dir_part.ends_with("/") || dir_part.ends_with("\\"))
					{
						full_rel = string::tformat("%s%s", dir_part, entry_str);
					}
					else
					{
						full_rel = string::tformat("%s/%s", dir_part, entry_str);
					}

					String full_resolved = string::tformat("%s/%s", resolved_dir, entry_str);
					bool is_directory = path::is_dir((Path)full_resolved);

					if (is_directory)
					{
						full_rel = string::tformat("%s/", full_rel);
					}
					else if (is_binary_extension(entry_str))
					{
						continue;
					}

					if (filter_part.len == 0)
					{
						int score = is_directory ? 5000 : 1000;
						candidates.push({ { .label = full_rel.copy(tmem), .target_path = full_rel.copy(tmem) }, score });
					}
					else
					{
						String entry_lower = entry_str.to_lower_tcopy();
						int score = 0;
						switch
						{
							case entry_lower == filter_lower:           score = 10000;
							case entry_lower.starts_with(filter_lower): score = 5000;
							case entry_lower.contains(filter_lower):    score = 2000;
							case fuzzy_match(entry_lower, filter_lower): score = 500;
						}
						if (score > 0)
						{
							if (is_directory) score += 500;
							candidates.push({ { .label = full_rel.copy(tmem), .target_path = full_rel.copy(tmem) }, score });
						}
					}
				}

				if (candidates.len() > 0)
				{
					sort::quicksort(&candidates, fn int (ScoredPickerItem a, ScoredPickerItem b) =>
						(a.score != b.score) ? (a.score > b.score ? -1 : 1) : a.item.label.compare_to(b.item.label));

					sz count = math::min(candidates.len(), (sz)100);
					for (sz i = 0; i < count; i++)
					{
						PickerItem it = candidates[i].item;
						self.picker.items.push({ .label = it.label.copy(mem), .target_path = it.target_path.copy(mem) });
					}
					return;
				}
			}
		}
	}

	ws.ensure_files();

	List{ScoredPickerItem} candidates;
	candidates.tinit(ws.files.len());

	foreach (filepath : ws.files)
	{
		int score = score_quick_open_match(filepath, query);
		if (score > 0)
		{
			candidates.push({ { .label = filepath.copy(tmem), .target_path = filepath.copy(tmem) }, score });
		}
	}

	if (candidates.len() > 0)
	{
		sort::quicksort(&candidates, fn int (ScoredPickerItem a, ScoredPickerItem b) =>
			(a.score != b.score) ? (a.score > b.score ? -1 : 1) : a.item.label.compare_to(b.item.label));

		sz count = math::min(candidates.len(), (sz)100);
		for (sz i = 0; i < count; i++)
		{
			PickerItem it = candidates[i].item;
			self.picker.items.push({ .label = it.label.copy(mem), .target_path = it.target_path.copy(mem) });
		}
	}
}

fn void ModalState.update_grep_results(&self, Workspace* ws) => @pool()
{
	self.clear_picker();
	String query = self.input.view();
	if (query.len == 0) return;

	ws.ensure_files();

	List{ScoredPickerItem} candidates;
	candidates.tinit(256);

	foreach (filepath : ws.files)
	{
		File? opened_file = file::open(filepath, "rb");
		if (catch opened_file) continue;
		File f = opened_file;
		defer (void)f.close();

		char[4096] scan_buffer;
		Scanner scanner;
		scanner.init(&f, &scan_buffer);

		int line_num     = 1;
		bool first_chunk = true;

		while (true)
		{
			char[]? scanned_line = scanner.scan("\n");
			if (catch scanned_line)
			{
				char[] remaining = scanner.flush();
				if (remaining.len > 0)
				{
					String line = (String)remaining;
					int score   = score_grep_match(line, query);
					if (score > 0)
					{
						String trimmed = line.trim();
						if (trimmed.len > 120) trimmed = trimmed[:120];
						String display = string::tformat("%s:%d: %s", filepath, line_num, trimmed);
						candidates.push({ { .label = display.copy(tmem), .target_path = filepath.copy(tmem), .line = line_num }, score });
					}
				}
				break;
			}

			char[] line_slice = scanned_line;
			if (first_chunk)
			{
				first_chunk = false;
				sz check_len = math::min(line_slice.len, (sz)1024);
				bool has_null = false;
				for (sz i = 0; i < check_len; i++)
				{
					if (line_slice[i] == '\0') { has_null = true; break; }
				}
				if (has_null) break;
			}

			String line = (String)line_slice;
			int score   = score_grep_match(line, query);
			if (score > 0)
			{
				String trimmed = line.trim();
				if (trimmed.len > 120) trimmed = trimmed[:120];
				String display = string::tformat("%s:%d: %s", filepath, line_num, trimmed);
				candidates.push({ { .label = display.copy(tmem), .target_path = filepath.copy(tmem), .line = line_num }, score });
				if (candidates.len() >= 500) break;
			}
			line_num++;
		}
		if (candidates.len() >= 500) break;
	}

	if (candidates.len() > 0)
	{
		sort::quicksort(&candidates, fn int (ScoredPickerItem a, ScoredPickerItem b) =>
			(a.score != b.score) ? (a.score > b.score ? -1 : 1) : a.item.label.compare_to(b.item.label));

		sz count = math::min(candidates.len(), (sz)200);
		for (sz i = 0; i < count; i++)
		{
			PickerItem it = candidates[i].item;
			self.picker.items.push({ .label = it.label.copy(mem), .target_path = it.target_path.copy(mem), .line = it.line });
		}
	}
}

fn void ModalState.update_outline_results(&self, Document* doc) => @pool()
{
	self.clear_picker();
	String query = self.input.view().to_lower_tcopy();

	SymbolIndex doc_lsp;
	doc_lsp.init(tmem);
	doc_lsp.index_source_text(doc.filepath, doc.table.to_tstring(), tmem);

	List{ScoredPickerItem} candidates;
	candidates.tinit(doc_lsp.symbols.len());

	foreach (&s : doc_lsp.symbols)
	{
		int score = 0;
		if (query.len == 0)
		{
			score = 1;
		}
		else
		{
			String n_lower = s.name.to_lower_tcopy();
			switch
			{
				case n_lower == query:           score = 1000;
				case n_lower.starts_with(query): score = 500;
				case n_lower.contains(query):    score = 200;
				case fuzzy_match(n_lower, query): score = 50;
			}
		}

		if (score > 0)
		{
			String kind_str = "[fn]";
			switch (s.kind)
			{
				case STRUCT:     kind_str = "[struct]";
				case ENUM:       kind_str = "[enum]";
				case MACRO:      kind_str = "[macro]";
				case TYPE_ALIAS: kind_str = "[alias]";
				case CONSTANT:   kind_str = "[const]";
				default:         kind_str = "[fn]";
			}
			String display = string::tformat("%s %s (Line %d)", kind_str, s.name, s.line);
			candidates.push({ { .label = display.copy(tmem), .target_path = doc.filepath.copy(tmem), .line = s.line, .col = s.col }, score });
		}
	}

	sort::quicksort(&candidates, fn int (ScoredPickerItem a, ScoredPickerItem b) =>
		(a.score != b.score) ? (a.score > b.score ? -1 : 1) : (a.item.line - b.item.line));

	sz count = math::min(candidates.len(), (sz)100);
	for (sz i = 0; i < count; i++)
	{
		PickerItem it = candidates[i].item;
		self.picker.items.push({
			.label       = it.label.copy(mem),
			.target_path = it.target_path.copy(mem),
			.line        = it.line,
			.col         = it.col
		});
	}
}
