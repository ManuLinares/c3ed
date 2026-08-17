module c3ed;
import std;

enum PendingSaveAction : char
{
	NONE,
	RUN_FILE,
	COMPILE_FILE
}

struct TerminalPanel
{
	bool is_open;
	bool is_running;
	List{String} lines;
	int scroll_line;
	bool auto_scroll;
	int height_px;
	String last_command;

	bool selecting;
	int sel_start_line;
	int sel_start_col;
	int sel_end_line;
	int sel_end_col;
}

fn void TerminalPanel.init(&self, Allocator allocator = mem)
{
	self.is_open = false;
	self.is_running = false;
	self.lines.init(allocator, 128);
	self.scroll_line = 0;
	self.auto_scroll = true;
	self.height_px = config::LAYOUT_METRICS.terminal_default_h;
	self.last_command = "";
	self.selecting = false;
	self.sel_start_line = 0;
	self.sel_start_col = 0;
	self.sel_end_line = 0;
	self.sel_end_col = 0;
}

fn void TerminalPanel.free(&self)
{
	foreach (l : self.lines)
	{
		if (l.len > 0) mem::free(l.ptr);
	}
	self.lines.free();
	if (self.last_command.len > 0) mem::free(self.last_command.ptr);
	*self = { };
}

fn bool TerminalPanel.has_selection(&self)
{
	return self.sel_start_line != self.sel_end_line || self.sel_start_col != self.sel_end_col;
}

fn void TerminalPanel.append_line(&self, String text)
{
	self.lines.push(text.copy(mem));
	if (self.lines.len() > 1000)
	{
		String removed = self.lines[0];
		if (removed.len > 0) mem::free(removed.ptr);
		self.lines.remove_at(0);
	}
	if (self.auto_scroll)
	{
		self.scroll_line = math::max(0, (int)self.lines.len() - 1);
	}
}

fn String? TerminalPanel.extract_selection(&self, Allocator allocator = tmem) => @pool()
{
	if (!self.has_selection() || self.lines.len() == 0) return NOT_FOUND~;

	int s_line = math::min(self.sel_start_line, self.sel_end_line);
	int e_line = math::max(self.sel_start_line, self.sel_end_line);
	s_line = math::clamp(s_line, 0, (int)self.lines.len() - 1);
	e_line = math::clamp(e_line, 0, (int)self.lines.len() - 1);

	DString ds;
	ds.tinit();

	for (int l = s_line; l <= e_line; l++)
	{
		String line_text = self.lines[(sz)l];
		int s_col = (l == s_line) ? math::min(self.sel_start_col, self.sel_end_col) : 0;
		int e_col = (l == e_line) ? math::max(self.sel_start_col, self.sel_end_col) : (int)line_text.len;

		s_col = math::clamp(s_col, 0, (int)line_text.len);
		e_col = math::clamp(e_col, 0, (int)line_text.len);

		if (s_col < e_col)
		{
			ds.append(line_text[s_col:e_col - s_col]);
		}
		if (l < e_line) ds.append_char('\n');
	}

	if (ds.len() == 0) return NOT_FOUND~;
	return ds.copy_str(allocator);
}

fn void TerminalPanel.execute(
	&self,
	DiagnosticStore* diagnostics,
	String[] cmd
) => @pool()
{
	self.is_open = true;
	self.is_running = true;
	self.append_line(string::tformat(">>> Running: %s", string::join(tmem, cmd, " ")));

	char[65536] buf;
	String? out = process::run_capture_stdout(&buf, cmd, options: STDERR_TO_STDOUT | INHERIT_ENV);
	self.is_running = false;

	if (try output_str = out)
	{
		Splitter split_lines = output_str.tokenize("\n");
		while (try l = split_lines.next())
		{
			self.append_line(l);
		}
		diagnostics.parse_output(output_str);
	}
	else
	{
		self.append_line("Execution failed.");
	}
}

struct CompletionItem
{
	String label;
	String detail;
	String insert_text;
	SymbolKind kind;
}

struct AutocompleteEngine
{
	List{CompletionItem} items;
	int selected_index;
	int scroll_offset;
	bool is_active;
}

fn void AutocompleteEngine.init(&self, Allocator allocator = mem)
{
	self.items.init(allocator, 64);
	self.selected_index = 0;
	self.scroll_offset = 0;
	self.is_active = false;
}

fn void AutocompleteEngine.free(&self, Allocator allocator = mem)
{
	self.clear_items();
	self.items.free();
	*self = { };
}

fn void AutocompleteEngine.clear_items(&self)
{
	foreach (&item : self.items)
	{
		if (item.label.len > 0) mem::free(item.label.ptr);
		if (item.detail.len > 0) mem::free(item.detail.ptr);
		if (item.insert_text.len > 0) mem::free(item.insert_text.ptr);
	}
	self.items.clear();
	self.selected_index = 0;
	self.scroll_offset = 0;
}

fn void AutocompleteEngine.collect_suggestions(
	&self,
	SymbolItem[] symbols,
	PieceTable* doc_table,
	BytePos cur_pos,
	String prefix,
	bool is_dot_access,
	bool is_scope_access,
	String parent_target = ""
) => @pool()
{
	self.clear_items();

	HashSet{String} seen;
	seen.tinit(256);

	String effective_parent = parent_target;
	if (is_dot_access && effective_parent.len > 0 && !effective_parent[0].is_upper())
	{
		BytePos scan_start = (cur_pos > 16384) ? cur_pos - 16384 : 0;
		String scope_text = doc_table.get_slice(scan_start, cur_pos, tmem);
		Splitter lines = scope_text.tokenize("\n");
		while (try l = lines.next())
		{
			String trimmed = l.trim();
			if (trimmed.contains(effective_parent))
			{
				Splitter words = trimmed.tokenize(" \t*&;,(){}");
				String prev_w = "";
				while (try w = words.next())
				{
					if (w == effective_parent && prev_w.len > 0 && prev_w[0].is_upper())
					{
						effective_parent = prev_w;
						break;
					}
					prev_w = w;
				}
			}
		}
	}

	if (is_dot_access)
	{
		foreach (&sym : symbols)
		{
			bool matches_parent = (effective_parent.len > 0 && sym.parent_type == effective_parent);
			if (!matches_parent && effective_parent.len > 0 && sym.parent_type.ends_with(effective_parent))
			{
				matches_parent = true;
			}

			if (matches_parent || (effective_parent.len == 0 && (sym.kind == FIELD || sym.kind == FUNCTION)))
			{
				if (prefix.len > 0 && !sym.name.to_lower_tcopy().starts_with(prefix.to_lower_tcopy())) continue;
				if (seen.contains(sym.name)) continue;
				seen.add(sym.name);

				self.items.push({
					.label       = sym.name.copy(mem),
					.detail      = sym.signature.len > 0 ? sym.signature.copy(mem) : sym.parent_type.copy(mem),
					.insert_text = sym.name.copy(mem),
					.kind        = sym.kind
				});
				if (self.items.len() >= 40) break;
			}
		}
		self.is_active = (self.items.len() > 0);
		return;
	}

	if (is_scope_access && parent_target.len > 0)
	{
		foreach (&sym : symbols)
		{
			if (sym.parent_type == parent_target || sym.parent_type.ends_with(parent_target))
			{
				if (prefix.len > 0 && !sym.name.to_lower_tcopy().starts_with(prefix.to_lower_tcopy())) continue;
				if (seen.contains(sym.name)) continue;
				seen.add(sym.name);

				self.items.push({
					.label       = sym.name.copy(mem),
					.detail      = sym.signature.copy(mem),
					.insert_text = sym.name.copy(mem),
					.kind        = sym.kind
				});
				if (self.items.len() >= 40) break;
			}
		}
		self.is_active = (self.items.len() > 0);
		return;
	}

	bool is_all_caps  = (prefix.len >= 2 && prefix[0].is_upper() && prefix[1].is_upper());
	bool is_type_name = (prefix.len >= 1 && prefix[0].is_upper());

	foreach (&sym : symbols)
	{
		if (is_all_caps && sym.kind != CONSTANT && sym.kind != FAULT && sym.kind != ENUM) continue;
		if (is_type_name && !is_all_caps && sym.kind != STRUCT && sym.kind != UNION && sym.kind != BITSTRUCT && sym.kind != ENUM && sym.kind != TYPE_ALIAS) continue;

		if (prefix.len > 0 && !sym.name.to_lower_tcopy().starts_with(prefix.to_lower_tcopy())) continue;
		if (seen.contains(sym.name)) continue;
		seen.add(sym.name);

		self.items.push({
			.label       = sym.name.copy(mem),
			.detail      = sym.signature.copy(mem),
			.insert_text = sym.name.copy(mem),
			.kind        = sym.kind
		});
		if (self.items.len() >= 30) break;
	}

	if (!is_all_caps)
	{
		foreach (tw : syntax::TokenType.TYPE.keywords)
		{
			if (prefix.len > 0 && !tw.to_lower_tcopy().starts_with(prefix.to_lower_tcopy())) continue;
			if (seen.contains(tw)) continue;
			seen.add(tw);
			self.items.push({
				.label       = tw.copy(mem),
				.detail      = "type".copy(mem),
				.insert_text = tw.copy(mem),
				.kind        = TYPE_ALIAS
			});
			if (self.items.len() >= 40) break;
		}

		foreach (kw : syntax::TokenType.KEYWORD.keywords)
		{
			if (prefix.len > 0 && !kw.to_lower_tcopy().starts_with(prefix.to_lower_tcopy())) continue;
			if (seen.contains(kw)) continue;
			seen.add(kw);
			self.items.push({
				.label       = kw.copy(mem),
				.detail      = "keyword".copy(mem),
				.insert_text = kw.copy(mem),
				.kind        = MACRO
			});
			if (self.items.len() >= 50) break;
		}
	}

	BytePos window_start = (cur_pos > 32768) ? cur_pos - 32768 : 0;
	BytePos window_end   = math::min(doc_table.len(), cur_pos + 32768);

	String local_str = doc_table.get_slice(window_start, window_end, tmem);
	Splitter words   = local_str.tokenize(" \t\n\r(){}[];:.,+-*/=<>!~&|^");

	while (try w = words.next())
	{
		if (w.len < 2 || w == prefix) continue;
		if (prefix.len > 0 && !w.to_lower_tcopy().starts_with(prefix.to_lower_tcopy())) continue;
		if (seen.contains(w)) continue;
		seen.add(w);

		self.items.push({
			.label       = w.copy(mem),
			.detail      = "word".copy(mem),
			.insert_text = w.copy(mem),
			.kind        = VARIABLE
		});
		if (self.items.len() >= 60) break;
	}

	self.is_active = (self.items.len() > 0);
}

struct Editor
{
	List{Tab} tabs;
	int active_tab_index;
	int pending_close_tab_index;
	int pending_reload_tab_index;
	PendingSaveAction pending_action_after_save;

	Workspace workspace;
	ModalState modal;
	TerminalPanel terminal;
	AutocompleteEngine autocomplete;

	float font_scale;
	KeyModifiers modifiers;
	bool mouse_down;
	int click_count;
	bool word_selecting;
	bool line_selecting;
	BytePos word_sel_anchor_start;
	BytePos word_sel_anchor_end;
	bool scrollbar_dragging;
	float scrollbar_drag_offset_y;
	bool minimap_dragging;
	float minimap_drag_offset_y;

	bool initialized;
	float blink_timer;
	bool cursor_visible;
	double last_click_time;
	Vec2 last_click_pos;
	float page_hold_timer;
	float save_msg_timer;
	bool should_exit;
}

fn Tab* Editor.active_tab(&self)
{
	if (self.tabs.len() == 0)
	{
		String uname = self.get_next_untitled_name(tmem);
		self.open_tab(uname, false, "");
	}
	if (self.active_tab_index < 0 || self.active_tab_index >= (int)self.tabs.len())
	{
		self.active_tab_index = 0;
	}
	return &self.tabs[(sz)self.active_tab_index];
}

fn Document* Editor.active_doc(&self) => &self.active_tab().doc;

fn void Editor.init(&self, String root_dir = ".")
{
	self.tabs.init(mem, 8);
	self.active_tab_index = 0;
	self.pending_close_tab_index = -1;
	self.pending_reload_tab_index = -1;
	self.pending_action_after_save = NONE;
	self.font_scale = config::settings.font_scale;
	self.workspace.init(mem, root_dir);
	self.modal.init(mem);
	self.terminal.init(mem);
	self.autocomplete.init(mem);
	self.initialized = true;
	self.blink_timer = 0.0f;
	self.cursor_visible = true;
	self.should_exit = false;
}

fn void Editor.free(&self)
{
	foreach (&t : self.tabs) t.free(mem);
	self.tabs.free();
	self.workspace.free(mem);
	self.modal.free();
	self.terminal.free();
	self.autocomplete.free(mem);
	font::cleanup_font();
	*self = { };
}

fn bool Editor.has_tab_or_file(&self, String candidate)
{
	foreach (&t : self.tabs)
	{
		if (t.doc.filepath == candidate) return true;
	}
	return file::exists(candidate);
}

fn String Editor.get_next_untitled_name(&self, Allocator allocator = mem) => @pool()
{
	int num = 1;
	while (true)
	{
		String candidate = (num == 1 && !self.has_tab_or_file("untitled.c3"))
			? "untitled.c3"
			: string::tformat("untitled-%d.c3", num);

		if (!self.has_tab_or_file(candidate))
		{
			return candidate.copy(allocator);
		}
		num++;
	}
}

fn int Editor.open_tab(
	&self,
	String filepath = "",
	bool file_specified = false,
	String initial_text = ""
)
{
	String actual_path = filepath;
	if (!file_specified && (actual_path.len == 0 || self.has_tab_or_file(actual_path)))
	{
		actual_path = self.get_next_untitled_name(tmem);
	}
	else if (actual_path.len == 0)
	{
		actual_path = "untitled.c3";
	}

	if (file_specified && actual_path.len > 0)
	{
		for (sz i = 0; i < self.tabs.len(); i++)
		{
			if (self.tabs[i].doc.is_file_specified && self.tabs[i].doc.filepath == actual_path)
			{
				self.active_tab_index = (int)i;
				self.reset_cursor_blink();
				return self.active_tab_index;
			}
		}

		if (self.tabs.len() == 1)
		{
			Tab* first = &self.tabs[0];
			if (!first.doc.is_file_specified && !first.doc.is_modified)
			{
				self.tabs[0].free(mem);
				self.tabs.remove_at(0);
			}
		}
	}

	Tab tab;
	if (file_specified && file::exists(actual_path))
	{
		FileMmap? mmap_res = file::mmap_open(actual_path, "r");
		if (try mm = mmap_res)
		{
			tab.init(mem, actual_path, file_specified, mm.bytes(), is_mmap: true, mmap_handle: mm);
		}
		else
		{
			char[]? data = file::load(mem, actual_path);
			tab.init(mem, actual_path, file_specified, data ?? {}, owns_buffer: true);
		}
		tab.doc.last_disk_mtime = file::last_modified(actual_path) ?? (Time)0;
	}
	else
	{
		tab.init(mem, actual_path, file_specified, (char[])initial_text.copy(mem), owns_buffer: true);
	}

	self.tabs.push(tab);
	self.active_tab_index = (int)self.tabs.len() - 1;
	self.active_tab().doc.rebuild_line_index();
	self.reset_cursor_blink();

	if (file_specified && file::exists(actual_path))
	{
		self.workspace.git.update(actual_path, self.active_tab().doc.get_total_lines());
	}
	return self.active_tab_index;
}

fn void Editor.request_close_tab(&self, int tab_idx)
{
	if (tab_idx < 0 || tab_idx >= (int)self.tabs.len()) return;
	Tab* t = &self.tabs[(sz)tab_idx];
	if (!t.doc.is_modified)
	{
		self.close_tab(tab_idx);
	}
	else
	{
		self.pending_close_tab_index = tab_idx;
		self.active_tab_index = tab_idx;
		self.modal.kind = CONFIRM_CLOSE_TAB;
		self.reset_cursor_blink();
	}
}

fn void Editor.close_tab(&self, int tab_idx)
{
	if (tab_idx < 0 || tab_idx >= (int)self.tabs.len()) return;

	self.tabs[tab_idx].free(mem);
	self.tabs.remove_at((sz)tab_idx);

	if (self.tabs.len() == 0)
	{
		String uname = self.get_next_untitled_name(tmem);
		self.open_tab(uname, false, "");
		self.active_tab_index = 0;
		self.reset_cursor_blink();
		return;
	}

	if (self.active_tab_index >= (int)self.tabs.len())
	{
		self.active_tab_index = (int)self.tabs.len() - 1;
	}
	self.reset_cursor_blink();
}

fn void Editor.reset_cursor_blink(&self)
{
	self.blink_timer = 0.0f;
	self.cursor_visible = true;
}

fn String Editor.get_modal_prompt(&self)
{
	String case_ind = self.modal.search_case_sensitive ? "Aa:ON" : "Aa:OFF";
	switch (self.modal.kind)
	{
		case GOTO_LINE:           return "GO TO LINE:";
		case FIND:                return string::tformat("FIND (%d matches) [Alt+C %s] - [Up/Down] Prev/Next [Esc] Close", self.modal.cached_match_count, case_ind);
		case REPLACE:             return string::tformat("FIND & REPLACE (%d matches) [Alt+C %s] - [Enter] Replace [Ctrl+Enter] Replace All [Tab] Switch", self.modal.cached_match_count, case_ind);
		case SAVE_AS:             return "SAVE FILE AS:";
		case QUICK_OPEN:          return string::tformat("QUICK FILE OPEN (Ctrl+O) - %d items", self.modal.picker.items.len());
		case GLOBAL_GREP:         return string::tformat("GLOBAL GREP (Ctrl+Shift+F) - %d matches", self.modal.picker.items.len());
		case SYMBOL_OUTLINE:      return string::tformat("DOCUMENT OUTLINE / SYMBOL PICKER (Ctrl+Shift+R) - %d symbols", self.modal.picker.items.len());
		case CONFIRM_EXIT:        return "UNSAVED CHANGES! Save all files before quitting?";
		case CONFIRM_CLOSE_TAB:   return "UNSAVED CHANGES! Save file before closing tab?";
		case CONFIRM_DISK_RELOAD: return "FILE MODIFIED EXTERNALLY! Reload disk version?";
		default:                  return "";
	}
}

fn Rect Editor.get_modal_rect(&self, LayoutMetrics* lm, int screen_w, int height)
{
	if (self.modal.kind == NONE) return { 0, 0, 0, 0 };

	String prompt = self.get_modal_prompt();
	int prompt_text_w = (int)prompt.len * lm.char_width;
	int modal_w       = math::max(config::LAYOUT_METRICS.modal_min_w, prompt_text_w + 48);

	if (self.modal.kind == QUICK_OPEN || self.modal.kind == GLOBAL_GREP || self.modal.kind == REPLACE || self.modal.kind == SYMBOL_OUTLINE)
	{
		modal_w = math::max(config::LAYOUT_METRICS.modal_wide_min_w, modal_w);
	}
	modal_w = math::min(modal_w, screen_w - config::LAYOUT_METRICS.tab_min_w_gap);

	int input_box_h = math::max(config::LAYOUT_METRICS.modal_input_box_h_min, lm.char_height + config::LAYOUT_METRICS.modal_input_box_padding);
	int modal_h;
	switch (self.modal.kind)
	{
		case CONFIRM_EXIT:
		case CONFIRM_CLOSE_TAB:
		case CONFIRM_DISK_RELOAD:
			modal_h = lm.char_height + input_box_h + 46;
		case REPLACE:
			modal_h = lm.char_height * 2 + input_box_h * 2 + 58;
		case QUICK_OPEN:
		case GLOBAL_GREP:
		case SYMBOL_OUTLINE:
			modal_h = config::LAYOUT_METRICS.modal_list_h;
		default:
			modal_h = lm.char_height + input_box_h + 46;
	}

	int modal_x = (screen_w - modal_w) / 2;
	int modal_y = (height - modal_h) / 3;

	return { (float)modal_x, (float)modal_y, (float)modal_w, (float)modal_h };
}

fn Rect Editor.get_case_toggle_rect(&self, LayoutMetrics* lm, int screen_w, int height)
{
	if (self.modal.kind != FIND && self.modal.kind != REPLACE) return { 0, 0, 0, 0 };
	Rect mrect = self.get_modal_rect(lm, screen_w, height);
	String prompt = self.get_modal_prompt();
	sz? tag_idx = prompt.index_of("[Alt+C");
	if (catch tag_idx) return { 0, 0, 0, 0 };

	int tag_pos = (int)tag_idx;
	String case_str = self.modal.search_case_sensitive ? "[Alt+C Aa:ON]" : "[Alt+C Aa:OFF]";
	int badge_x = (int)mrect.x + config::LAYOUT_METRICS.modal_padding_x + tag_pos * lm.char_width;
	int badge_w = (int)case_str.len * lm.char_width + 8;
	int badge_y = (int)mrect.y + 12;
	int badge_h = lm.char_height + 4;

	return { (float)(badge_x - 4), (float)badge_y, (float)badge_w, (float)badge_h };
}

fn void Editor.confirm_save_action(&self)
{
	switch (self.modal.kind)
	{
		case CONFIRM_CLOSE_TAB:
			int target_idx = self.pending_close_tab_index;
			if (target_idx >= 0 && target_idx < (int)self.tabs.len())
			{
				Tab* t = &self.tabs[(sz)target_idx];
				if (!t.doc.is_file_specified || t.doc.filepath.len == 0)
				{
					self.active_tab_index = target_idx;
					self.modal.kind = SAVE_AS;
					self.modal.input.set_text(t.doc.filepath);
				}
				else
				{
					file::save(t.doc.filepath, (char[])t.doc.table.to_tstring())!!;
					t.doc.is_modified = false;
					self.save_msg_timer = config::TIMING.save_msg_duration;
					int to_close = target_idx;
					self.pending_close_tab_index = -1;
					self.modal.kind = NONE;
					self.close_tab(to_close);
				}
			}
			else
			{
				self.modal.kind = NONE;
			}
		case CONFIRM_EXIT:
			foreach (&t : self.tabs)
			{
				if (t.doc.is_modified && t.doc.filepath.len > 0)
				{
					file::save(t.doc.filepath, (char[])t.doc.table.to_tstring())!!;
				}
			}
			self.should_exit = true;
		case CONFIRM_DISK_RELOAD:
			int reload_idx = self.pending_reload_tab_index >= 0 ? self.pending_reload_tab_index : self.active_tab_index;
			if (reload_idx >= 0 && reload_idx < (int)self.tabs.len())
			{
				Tab* t = &self.tabs[(sz)reload_idx];
				if (t.doc.is_file_specified && t.doc.filepath.len > 0)
				{
					t.doc.table.free();
					char[]? data = file::load(mem, t.doc.filepath);
					t.doc.table.init(mem, data ?? {}, owns_buffer: true);
					t.doc.rebuild_line_index();
					t.doc.is_modified = false;
					self.workspace.git.update(t.doc.filepath, t.doc.get_total_lines());
					self.save_msg_timer = config::TIMING.save_msg_duration;
				}
			}
			self.pending_reload_tab_index = -1;
			self.modal.kind = NONE;
		default: break;
	}
}

fn void Editor.confirm_discard_action(&self)
{
	switch (self.modal.kind)
	{
		case CONFIRM_CLOSE_TAB:
			int target_idx = self.pending_close_tab_index;
			self.pending_close_tab_index = -1;
			self.modal.kind = NONE;
			if (target_idx >= 0 && target_idx < (int)self.tabs.len())
			{
				self.close_tab(target_idx);
			}
		case CONFIRM_EXIT:
			self.should_exit = true;
		case CONFIRM_DISK_RELOAD:
			self.modal.kind = NONE;
		default: break;
	}
}

fn void Editor.confirm_cancel_action(&self)
{
	self.pending_close_tab_index = -1;
	self.modal.kind = NONE;
}

fn void Editor.goto_definition(&self, LayoutMetrics* lm) => @pool()
{
	Tab* tab = self.active_tab();
	Document* doc = &tab.doc;
	Cursor* cur = doc.primary_cursor();
	int cur_line = doc.get_line(cur.pos) + 1;

	TextRange bounds = get_word_bounds(&doc.table, cur.pos);
	if (bounds.start >= bounds.end) return;

	DString name_ds;
	name_ds.tinit();
	doc.table.append_range_to_dstring(&name_ds, bounds.start, bounds.end);
	String word = name_ds.str_view();
	if (word.len == 0) return;

	SymbolIndex local_lsp;
	local_lsp.init(tmem);
	local_lsp.index_source_text(doc.filepath, doc.table.to_tstring(), tmem);

	SymbolItem*? local_sym = local_lsp.find_symbol_closest(word, cur_line);
	if (try sym = local_sym)
	{
		BytePos target_pos = doc.get_pos_from_line_col(sym.line - 1, sym.col - 1);
		doc.cursors.clear();
		doc.cursors.push({ target_pos, target_pos, sym.col - 1 });
		tab.ensure_pos_visible(target_pos, lm.visible_lines, lm.visible_cols);
		self.reset_cursor_blink();
		return;
	}

	for (sz i = 0; i < self.tabs.len(); i++)
	{
		if ((int)i == self.active_tab_index) continue;
		Tab* other_tab = &self.tabs[i];
		SymbolIndex other_lsp;
		other_lsp.init(tmem);
		other_lsp.index_source_text(other_tab.doc.filepath, other_tab.doc.table.to_tstring(), tmem);
		if (try sym = other_lsp.find_symbol_closest(word, 0))
		{
			self.active_tab_index = (int)i;
			Tab* active = self.active_tab();
			BytePos target_pos = active.doc.get_pos_from_line_col(sym.line - 1, sym.col - 1);
			active.doc.cursors.clear();
			active.doc.cursors.push({ target_pos, target_pos, sym.col - 1 });
			active.ensure_pos_visible(target_pos, lm.visible_lines, lm.visible_cols);
			self.reset_cursor_blink();
			return;
		}
	}

	SymbolItem*? sym_opt = self.workspace.lsp.find_symbol_closest(word, 0);
	if (try sym = sym_opt)
	{
		self.open_tab(sym.filepath, true);
		Tab* new_tab = self.active_tab();

		BytePos target_pos = new_tab.doc.get_pos_from_line_col(sym.line - 1, sym.col - 1);
		new_tab.doc.cursors.clear();
		new_tab.doc.cursors.push({ target_pos, target_pos, sym.col - 1 });
		new_tab.ensure_pos_visible(target_pos, lm.visible_lines, lm.visible_cols);
		self.reset_cursor_blink();
	}
}

fn void Editor.goto_next_symbol(&self, LayoutMetrics* lm) => @pool()
{
	Tab* tab = self.active_tab();
	Document* doc = &tab.doc;
	Cursor* cur = doc.primary_cursor();
	int cur_l = doc.get_line(cur.pos) + 1;

	SymbolIndex doc_lsp;
	doc_lsp.init(tmem);
	doc_lsp.index_source_text(doc.filepath, doc.table.to_tstring(), tmem);

	if (doc_lsp.symbols.len() == 0) return;

	SymbolItem* target_sym = null;
	foreach (&s : doc_lsp.symbols)
	{
		if (s.line > cur_l)
		{
			target_sym = s;
			break;
		}
	}
	if (target_sym == null)
	{
		target_sym = &doc_lsp.symbols[0];
	}

	SymbolItem* s = target_sym;
	BytePos target_pos = doc.get_pos_from_line_col(s.line - 1, s.col - 1);
	doc.cursors.clear();
	doc.cursors.push({ target_pos, target_pos, s.col - 1 });
	tab.ensure_pos_visible(target_pos, lm.visible_lines, lm.visible_cols);
	self.reset_cursor_blink();
}

fn void Editor.trigger_autocomplete_at_cursor(&self) => @pool()
{
	Tab* tab = self.active_tab();
	Document* doc = &tab.doc;
	Cursor* cur = doc.primary_cursor();
	BytePos p = cur.pos;

	String prefix = "";
	String parent = "";
	bool is_dot = false;
	bool is_scope = false;

	if (p > 0)
	{
		char prev_c = doc.table.char_at(p - 1);
		if (prev_c == '.')
		{
			is_dot = true;
			TextRange b = get_word_bounds(&doc.table, p - 1);
			parent = doc.table.get_slice(b.start, b.end, tmem);
		}
		else if (p > 1 && prev_c == ':' && doc.table.char_at(p - 2) == ':')
		{
			is_scope = true;
			TextRange b = get_word_bounds(&doc.table, p - 2);
			parent = doc.table.get_slice(b.start, b.end, tmem);
		}
		else
		{
			TextRange b = get_word_bounds(&doc.table, p);
			prefix = doc.table.get_slice(b.start, p, tmem);
			if (b.start > 0 && doc.table.char_at(b.start - 1) == '.')
			{
				is_dot = true;
				TextRange pb = get_word_bounds(&doc.table, b.start - 1);
				parent = doc.table.get_slice(pb.start, pb.end, tmem);
			}
		}
	}

	self.autocomplete.collect_suggestions(
		self.workspace.lsp.symbols.array_view(),
		&doc.table,
		cur.pos,
		prefix,
		is_dot,
		is_scope,
		parent
	);

	self.autocomplete.is_active = (self.autocomplete.items.len() > 0);
	if (self.autocomplete.is_active)
	{
		self.autocomplete.selected_index = 0;
		self.autocomplete.scroll_offset = 0;
		self.reset_cursor_blink();
	}
}

fn void Editor.run_or_compile_file(&self, bool run, PendingSaveAction action) => @pool()
{
	Tab* tab = self.active_tab();
	if (!tab.doc.is_file_specified || tab.doc.filepath.len == 0)
	{
		self.modal.kind = SAVE_AS;
		self.modal.input.set_text(tab.doc.filepath);
		self.pending_action_after_save = action;
		return;
	}
	if (tab.doc.is_modified)
	{
		file::save(tab.doc.filepath, (char[])tab.doc.table.to_tstring())!!;
		tab.doc.is_modified = false;
		tab.doc.last_disk_mtime = file::last_modified(tab.doc.filepath) ?? (Time)0;
		self.workspace.git.update(tab.doc.filepath, tab.doc.get_total_lines());
		self.save_msg_timer = config::TIMING.save_msg_duration;
	}
	String[*] cmd = run
		? { "c3c", "compile-run", tab.doc.filepath }
		: { "c3c", "compile", tab.doc.filepath };

	self.terminal.execute(&self.workspace.diagnostics, cmd[..]);
}

fn void Editor.build_project(&self) => @pool()
{
	Tab* tab = self.active_tab();
	if (file::exists("project.json"))
	{
		String[*] cmd = { "c3c", "build" };
		self.terminal.execute(&self.workspace.diagnostics, cmd[..]);
	}
	else if (tab.doc.is_file_specified && tab.doc.filepath.len > 0)
	{
		self.run_or_compile_file(false, COMPILE_FILE);
	}
}

fn void Editor.run_project(&self) => @pool()
{
	Tab* tab = self.active_tab();
	if (file::exists("project.json"))
	{
		String[*] cmd = { "c3c", "run" };
		self.terminal.execute(&self.workspace.diagnostics, cmd[..]);
	}
	else if (tab.doc.is_file_specified && tab.doc.filepath.len > 0)
	{
		self.run_or_compile_file(true, RUN_FILE);
	}
}

fn String get_session_file_path(Allocator allocator, String workspace_dir) => @pool()
{
	Path? home = path::home_directory(tmem);
	if (catch home) return "";

	Path config_dir = home.tappend(".config") ?? home;
	Path c3ed_dir = config_dir.tappend("c3ed") ?? config_dir;
	(void)path::mkdir(c3ed_dir, recursive: true);

	uint hash_val = workspace_dir.hash();
	String fname = string::tformat("session_%x.ini", hash_val);
	Path? full_path = c3ed_dir.tappend(fname);
	if (catch full_path) return "";
	return ((String)full_path).copy(allocator);
}

fn void Editor.save_session(&self, String workspace_dir) => @pool()
{
	String spath = get_session_file_path(tmem, workspace_dir);
	if (spath.len == 0) return;

	Object* root = object::new_obj(tmem);

	Object* sess_sec = object::new_obj(tmem);
	sess_sec.set("active_tab", string::tformat("%d", self.active_tab_index));
	sess_sec.set("font_scale", string::tformat("%f", self.font_scale));
	sess_sec.set("terminal_open", self.terminal.is_open ? "true" : "false");
	sess_sec.set("tab_count", string::tformat("%d", self.tabs.len()));
	root.set("session", sess_sec);

	for (sz i = 0; i < self.tabs.len(); i++)
	{
		Tab* t = &self.tabs[i];
		Cursor* c = (t.doc.cursors.len() > 0) ? &t.doc.cursors[0] : null;
		BytePos pos = c ? c.pos : 0;
		BytePos anchor = c ? c.anchor : 0;

		Object* tab_sec = object::new_obj(tmem);
		tab_sec.set("filepath", t.doc.filepath);
		tab_sec.set("is_file_specified", t.doc.is_file_specified ? "true" : "false");
		tab_sec.set("scroll_line", string::tformat("%d", t.scroll_line));
		tab_sec.set("scroll_col", string::tformat("%d", t.scroll_col));
		tab_sec.set("cursor_pos", string::tformat("%d", (long)pos));
		tab_sec.set("cursor_anchor", string::tformat("%d", (long)anchor));

		root.set(string::tformat("tab_%d", i), tab_sec);
	}

	String encoded = ini::encode(tmem, root);
	(void)file::save(spath, (char[])encoded);
}

fn bool Editor.load_session(&self, String workspace_dir) => @pool()
{
	String spath = get_session_file_path(tmem, workspace_dir);
	if (spath.len == 0 || !file::exists(spath)) return false;

	char[]? content_opt = file::load(tmem, spath);
	if (catch content_opt) return false;
	String content = (String)content_opt;

	Object*? ini_obj = ini::parse(tmem, content);
	if (catch ini_obj) return false;
	Object* dom = ini_obj;

	Object*? sess_sec_opt = dom.get("session");
	if (catch sess_sec_opt) return false;
	Object* sess_sec = sess_sec_opt;

	int active_tab = sess_sec.get_string("active_tab").to_int() ?? sess_sec.get_int("active_tab") ?? 0;
	int tab_count  = sess_sec.get_string("tab_count").to_int() ?? sess_sec.get_int("tab_count") ?? 0;
	double scale   = sess_sec.get_string("font_scale").to_double() ?? sess_sec.get_float("font_scale") ?? 1.0;
	bool term_open = (sess_sec.get_string("terminal_open") ?? "false") == "true";

	if (tab_count <= 0) return false;

	while (self.tabs.len() > 0)
	{
		self.close_tab(0);
	}

	for (int i = 0; i < tab_count; i++)
	{
		String sec_name = string::tformat("tab_%d", i);
		Object*? t_sec_opt = dom.get(sec_name);
		if (catch t_sec_opt) continue;
		Object* t_sec = t_sec_opt;

		String fpath = t_sec.get_string("filepath") ?? "untitled.c3";
		bool f_spec  = (t_sec.get_string("is_file_specified") ?? "false") == "true";

		int s_line       = t_sec.get_string("scroll_line").to_int() ?? t_sec.get_int("scroll_line") ?? 0;
		int s_col        = t_sec.get_string("scroll_col").to_int() ?? t_sec.get_int("scroll_col") ?? 0;
		BytePos c_pos    = (BytePos)(t_sec.get_string("cursor_pos").to_int() ?? t_sec.get_int("cursor_pos") ?? 0);
		BytePos c_anc    = (BytePos)(t_sec.get_string("cursor_anchor").to_int() ?? t_sec.get_int("cursor_anchor") ?? 0);

		self.open_tab(fpath, f_spec);
		Tab* new_tab = self.active_tab();
		new_tab.scroll_line = s_line;
		new_tab.scroll_col = s_col;
		c_pos = math::min(c_pos, new_tab.doc.table.len());
		c_anc = math::min(c_anc, new_tab.doc.table.len());
		new_tab.doc.cursors.clear();
		new_tab.doc.cursors.push({ c_pos, c_anc, new_tab.doc.get_col(c_pos) });
	}

	self.active_tab_index = math::clamp(active_tab, 0, math::max(0, (int)self.tabs.len() - 1));
	self.font_scale = (float)scale;
	self.terminal.is_open = term_open;
	self.reset_cursor_blink();
	return (self.tabs.len() > 0);
}

macro void @move_cursors(doc, shift; @body(Cursor* cur))
{
	foreach (&cur : doc.cursors)
	{
		@body(cur);
		if (!shift) cur.anchor = cur.pos;
		cur.target_col = doc.get_col(cur.pos);
	}
	doc.normalize_cursors();
}

fn bool Editor.handle_tab_command(&self, EditorCommand cmd)
{
	switch (cmd)
	{
		case CMD_NEW_TAB:
			String uname = self.get_next_untitled_name(tmem);
			self.open_tab(uname, false, "");
			return true;

		case CMD_CLOSE_TAB:
			self.request_close_tab(self.active_tab_index);
			return true;

		case CMD_NEXT_TAB:
			if (self.tabs.len() > 1)
			{
				self.active_tab_index = (self.active_tab_index + 1) % (int)self.tabs.len();
				self.reset_cursor_blink();
			}
			return true;

		case CMD_PREV_TAB:
			if (self.tabs.len() > 1)
			{
				self.active_tab_index = (self.active_tab_index + (int)self.tabs.len() - 1) % (int)self.tabs.len();
				self.reset_cursor_blink();
			}
			return true;

		case CMD_TAB_1:
		case CMD_TAB_2:
		case CMD_TAB_3:
		case CMD_TAB_4:
		case CMD_TAB_5:
		case CMD_TAB_6:
		case CMD_TAB_7:
		case CMD_TAB_8:
		case CMD_TAB_9:
			int target_idx = (int)cmd - (int)EditorCommand.CMD_TAB_1;
			if (target_idx < (int)self.tabs.len())
			{
				self.active_tab_index = target_idx;
				self.reset_cursor_blink();
			}
			return true;

		default:
			return false;
	}
}

fn bool Editor.handle_nav_command(&self, EditorCommand cmd, LayoutMetrics* lm)
{
	Tab* tab      = self.active_tab();
	Document* doc = &tab.doc;
	int tot_lines = doc.get_total_lines();

	switch (cmd)
	{
		case CMD_MOVE_LEFT:
			@move_cursors(doc, self.modifiers.shift; cur)
			{
				cur.pos = (!self.modifiers.shift && cur.has_selection())
					? cur.sel_start()
					: get_prev_char_pos(&doc.table, cur.pos);
			};
			return true;

		case CMD_MOVE_RIGHT:
			@move_cursors(doc, self.modifiers.shift; cur)
			{
				cur.pos = (!self.modifiers.shift && cur.has_selection())
					? cur.sel_end()
					: get_next_char_pos(&doc.table, cur.pos);
			};
			return true;

		case CMD_MOVE_WORD_LEFT:
			@move_cursors(doc, self.modifiers.shift; cur) { cur.pos = get_prev_word_pos(&doc.table, cur.pos); };
			return true;

		case CMD_MOVE_WORD_RIGHT:
			@move_cursors(doc, self.modifiers.shift; cur) { cur.pos = get_next_word_pos(&doc.table, cur.pos); };
			return true;

		case CMD_MOVE_UP:
			@move_cursors(doc, self.modifiers.shift; cur)
			{
				int line = doc.get_line(cur.pos);
				cur.pos = (line > 0) ? doc.get_pos_from_line_col(line - 1, cur.target_col) : 0;
			};
			return true;

		case CMD_MOVE_DOWN:
			@move_cursors(doc, self.modifiers.shift; cur)
			{
				int line = doc.get_line(cur.pos);
				cur.pos = (line < tot_lines - 1) ? doc.get_pos_from_line_col(line + 1, cur.target_col) : doc.table.len();
			};
			return true;

		case CMD_MOVE_LINE_START:
			@move_cursors(doc, self.modifiers.shift; cur) { cur.pos = doc.get_line_start(cur.pos); };
			return true;

		case CMD_MOVE_LINE_END:
			@move_cursors(doc, self.modifiers.shift; cur) { cur.pos = doc.get_line_end(cur.pos); };
			return true;

		case CMD_MOVE_FILE_START:
			doc.cursors.clear();
			doc.cursors.push({ 0, 0, 0 });
			return true;

		case CMD_MOVE_FILE_END:
			doc.cursors.clear();
			BytePos end_p = doc.table.len();
			doc.cursors.push({ end_p, end_p, doc.get_col(end_p) });
			return true;

		case CMD_PAGE_UP:
			int step_up = 1 + math::clamp((int)(self.page_hold_timer * config::TIMING.page_hold_multiplier), 0, config::TIMING.max_page_speed);
			int move_up = lm.visible_lines * step_up;
			@move_cursors(doc, self.modifiers.shift; cur)
			{
				int l = math::max(0, doc.get_line(cur.pos) - move_up);
				cur.pos = doc.get_pos_from_line_col(l, cur.target_col);
			};
			return true;

		case CMD_PAGE_DOWN:
			int step_down = 1 + math::clamp((int)(self.page_hold_timer * config::TIMING.page_hold_multiplier), 0, config::TIMING.max_page_speed);
			int move_down = lm.visible_lines * step_down;
			@move_cursors(doc, self.modifiers.shift; cur)
			{
				int l = math::min(tot_lines - 1, doc.get_line(cur.pos) + move_down);
				cur.pos = doc.get_pos_from_line_col(l, cur.target_col);
			};
			return true;

		case CMD_JUMP_MATCHING_BRACKET:
			doc.jump_to_matching_bracket(self.modifiers.shift);
			return true;

		case CMD_SELECT_ALL:
			doc.cursors.clear();
			doc.cursors.push({ doc.table.len(), 0, doc.get_col(doc.table.len()) });
			return true;

		case CMD_SELECT_TO_TOP:
			@move_cursors(doc, true; cur) { cur.pos = 0; };
			return true;

		case CMD_SELECT_TO_BOTTOM:
			@move_cursors(doc, true; cur) { cur.pos = doc.table.len(); };
			return true;

		case CMD_CLEAR_SELECTION:
			if (self.autocomplete.is_active)
			{
				self.autocomplete.is_active = false;
				return false;
			}
			if (doc.cursors.len() > 1)
			{
				Cursor prim = doc.cursors[0];
				doc.cursors.clear();
				doc.cursors.push(prim);
			}
			else
			{
				doc.primary_cursor().anchor = doc.primary_cursor().pos;
			}
			return true;

		case CMD_ADD_CURSOR_ABOVE:
			doc.add_cursor_vertical(true);
			return true;

		case CMD_ADD_CURSOR_BELOW:
			doc.add_cursor_vertical(false);
			return true;

		case CMD_ADD_NEXT_OCCURRENCE:
			doc.add_next_occurrence(tab, lm.visible_lines, lm.visible_cols);
			self.reset_cursor_blink();
			return false;

		case CMD_GOTO_DEFINITION:
			self.goto_definition(lm);
			return true;

		case CMD_GOTO_NEXT_SYMBOL:
			self.goto_next_symbol(lm);
			return true;

		default:
			return false;
	}
}

fn bool Editor.handle_edit_command(&self, EditorCommand cmd)
{
	Tab* tab      = self.active_tab();
	Document* doc = &tab.doc;

	switch (cmd)
	{
		case CMD_BACKSPACE:
			doc.handle_backspace();
			return true;

		case CMD_DELETE:
			doc.handle_delete();
			return true;

		case CMD_DELETE_WORD_LEFT:
			doc.delete_word_left();
			return true;

		case CMD_DELETE_WORD_RIGHT:
			doc.delete_word_right();
			return true;

		case CMD_ENTER:
			doc.handle_enter();
			return true;

		case CMD_INSERT_TAB:
			bool has_any_selection = false;
			foreach (&cur : doc.cursors)
			{
				if (cur.has_selection()) { has_any_selection = true; break; }
			}
			switch
			{
				case self.modifiers.shift: doc.indent_block(true);
				case has_any_selection:    doc.indent_block(false);
				default:                   doc.insert_codepoint('\t');
			}
			return true;

		case CMD_INDENT:
			bool has_sel = false;
			foreach (&cur : doc.cursors)
			{
				if (cur.has_selection()) { has_sel = true; break; }
			}
			has_sel ? doc.indent_block(false) : doc.insert_codepoint('\t');
			return true;

		case CMD_OUTDENT:
			doc.indent_block(true);
			return true;

		case CMD_DUPLICATE_LINE:
			doc.duplicate_line();
			return true;

		case CMD_DELETE_LINE:
			doc.delete_line();
			return true;

		case CMD_MOVE_LINE_UP:
			doc.move_lines_vertical(true);
			return true;

		case CMD_MOVE_LINE_DOWN:
			doc.move_lines_vertical(false);
			return true;

		case CMD_TOGGLE_COMMENT:
			doc.toggle_comment();
			return true;

		case CMD_TO_UPPERCASE:
			doc.convert_case_selection(true);
			return true;

		case CMD_TO_LOWERCASE:
			doc.convert_case_selection(false);
			return true;

		case CMD_COPY:
			DString tmp;
			tmp.tinit();
			foreach (&cur : doc.cursors)
			{
				if (cur.has_selection())
				{
					if (tmp.len() > 0) tmp.append_char('\n');
					doc.table.append_range_to_dstring(&tmp, cur.sel_start(), cur.sel_end());
				}
			}
			if (tmp.len() > 0)
			{
				gfx::set_clipboard(tmp.str_view());
			}
			return false;

		case CMD_CUT:
			DString tmp;
			tmp.tinit();
			foreach (&cur : doc.cursors)
			{
				if (cur.has_selection())
				{
					if (tmp.len() > 0) tmp.append_char('\n');
					doc.table.append_range_to_dstring(&tmp, cur.sel_start(), cur.sel_end());
				}
			}
			if (tmp.len() > 0)
			{
				gfx::set_clipboard(tmp.str_view());
			}
			doc.delete_selection();
			return true;

		case CMD_PASTE:
			String? clip_opt = gfx::get_clipboard(tmem);
			if (try clip = clip_opt)
			{
				doc.@mutate_cursors(; cur, delta)
				{
					BytePos s = cur.sel_start();
					BytePos e = cur.sel_end();
					doc.apply_cursor_edit(cur, s, e, (char[])clip, delta);
				};
				return true;
			}
			return false;

		case CMD_UNDO:
			doc.undo();
			return true;

		case CMD_REDO:
			doc.redo();
			return true;

		default:
			return false;
	}
}

fn bool Editor.handle_search_modal_command(&self, EditorCommand cmd, LayoutMetrics* lm)
{
	Tab* tab      = self.active_tab();
	Document* doc = &tab.doc;

	switch (cmd)
	{
		case CMD_OPEN_FIND:
		case CMD_OPEN_REPLACE:
			self.modal.kind = (cmd == CMD_OPEN_FIND) ? FIND : REPLACE;
			if (doc.primary_cursor().has_selection())
			{
				BytePos s = doc.primary_cursor().sel_start();
				BytePos e = doc.primary_cursor().sel_end();
				if (doc.get_line(s) == doc.get_line(e))
				{
					DString sel_str;
					sel_str.tinit();
					doc.table.append_range_to_dstring(&sel_str, s, e);
					self.modal.input.set_text(sel_str.str_view());
				}
			}
			self.modal.focus_field = 0;
			self.modal.update_cached_search_matches(doc);
			return false;

		case CMD_FIND_NEXT:
			self.modal.find_next(doc, false, tab, lm.visible_lines, lm.visible_cols);
			return false;

		case CMD_FIND_PREV:
			self.modal.find_next(doc, true, tab, lm.visible_lines, lm.visible_cols);
			return false;

		case CMD_REPLACE_NEXT:
			self.modal.replace_next(doc, tab, lm.visible_lines, lm.visible_cols);
			return false;

		case CMD_REPLACE_ALL:
			self.modal.replace_all(doc, tab, lm.visible_lines, lm.visible_cols);
			return false;

		case CMD_TOGGLE_CASE_SENSITIVITY:
			if (self.modal.kind == FIND || self.modal.kind == REPLACE)
			{
				self.modal.search_case_sensitive = !self.modal.search_case_sensitive;
				self.modal.update_cached_search_matches(doc);
				if (self.modal.kind == FIND || (self.modal.kind == REPLACE && self.modal.focus_field == 0))
				{
					self.modal.find_from_current(doc, tab, lm.visible_lines, lm.visible_cols);
				}
			}
			return false;

		case CMD_OPEN_QUICK_OPEN:
			self.modal.kind = QUICK_OPEN;
			self.modal.input.clear();
			self.workspace.refresh_files();
			self.modal.update_quick_open_results(&self.workspace);
			return false;

		case CMD_OPEN_GLOBAL_GREP:
			self.modal.kind = GLOBAL_GREP;
			self.modal.input.clear();
			self.workspace.refresh_files();
			self.modal.update_grep_results(&self.workspace);
			return false;

		case CMD_OPEN_GOTO_LINE:
			self.modal.kind = GOTO_LINE;
			self.modal.input.clear();
			return false;

		case CMD_OPEN_SYMBOL_OUTLINE:
			self.modal.kind = SYMBOL_OUTLINE;
			self.modal.input.clear();
			self.modal.update_outline_results(doc);
			return false;

		case CMD_TRIGGER_AUTOCOMPLETE:
			self.trigger_autocomplete_at_cursor();
			return false;

		default:
			return false;
	}
}

fn bool Editor.handle_workspace_command(&self, EditorCommand cmd)
{
	Tab* tab      = self.active_tab();
	Document* doc = &tab.doc;

	switch (cmd)
	{
		case CMD_BUILD_PROJECT:
			self.build_project();
			return false;

		case CMD_COMPILE_THIS_FILE:
			self.run_or_compile_file(false, COMPILE_FILE);
			return false;

		case CMD_RUN_PROJECT:
			self.run_project();
			return false;

		case CMD_RUN_THIS_FILE:
			self.run_or_compile_file(true, RUN_FILE);
			return false;

		case CMD_TOGGLE_TERMINAL:
			self.terminal.is_open = !self.terminal.is_open;
			return false;

		case CMD_SAVE_FILE:
			if (!doc.is_file_specified)
			{
				self.modal.kind = SAVE_AS;
				self.modal.input.set_text(doc.filepath);
			}
			else
			{
				file::save(doc.filepath, (char[])doc.table.to_tstring())!!;
				doc.is_modified = false;
				doc.last_disk_mtime = file::last_modified(doc.filepath) ?? (Time)0;
				self.workspace.git.update(doc.filepath, doc.get_total_lines());
				self.save_msg_timer = config::TIMING.save_msg_duration;
			}
			return false;

		case CMD_SAVE_AS:
			self.modal.kind = SAVE_AS;
			self.modal.input.set_text(doc.filepath);
			return false;

		case CMD_QUIT:
			bool any_modified = false;
			foreach (&t : self.tabs)
			{
				if (t.doc.is_modified) { any_modified = true; break; }
			}
			if (any_modified)
			{
				self.modal.kind = CONFIRM_EXIT;
			}
			else
			{
				self.should_exit = true;
			}
			return false;

		case CMD_ZOOM_IN:
			self.font_scale = math::min(config::LAYOUT_METRICS.max_font_scale, self.font_scale + config::LAYOUT_METRICS.font_zoom_step);
			return false;

		case CMD_ZOOM_OUT:
			self.font_scale = math::max(config::LAYOUT_METRICS.min_font_scale, self.font_scale - config::LAYOUT_METRICS.font_zoom_step);
			return false;

		default:
			return false;
	}
}

fn void Editor.dispatch_command(&self, EditorCommand cmd, LayoutMetrics* lm, float dt)
{
	if (cmd == CMD_NONE) return;

	bool update_view = false;

	if (self.handle_tab_command(cmd))
	{
		update_view = true;
	}
	else if (self.handle_nav_command(cmd, lm))
	{
		update_view = true;
	}
	else if (self.handle_edit_command(cmd))
	{
		update_view = true;
	}
	else if (self.handle_search_modal_command(cmd, lm))
	{
		update_view = true;
	}
	else if (self.handle_workspace_command(cmd))
	{
		update_view = true;
	}

	if (update_view)
	{
		self.active_tab().ensure_cursor_visible(lm.visible_lines, lm.visible_cols);
	}
}