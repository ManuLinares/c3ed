module c3ed;
import std;

Editor editor;
String current_workspace = ".";

fn bool key_pressed_or_repeat(Key key) => gfx::is_key_pressed(key) || gfx::is_key_repeat(key);

macro void @handle_list_picker_keys(#picker, int visible_rows)
{
	#picker.clamp_view(visible_rows);
	if (key_pressed_or_repeat(PAGE_UP))
	{
		#picker.page_up();
		editor.reset_cursor_blink();
	}
	if (key_pressed_or_repeat(PAGE_DOWN))
	{
		#picker.page_down();
		editor.reset_cursor_blink();
	}
	if (key_pressed_or_repeat(UP) || (editor.modifiers.ctrl && (gfx::is_key_pressed(P) || gfx::is_key_pressed(K))))
	{
		#picker.select_prev();
		editor.reset_cursor_blink();
	}
	if (key_pressed_or_repeat(DOWN) || (editor.modifiers.ctrl && (gfx::is_key_pressed(N) || gfx::is_key_pressed(J))))
	{
		#picker.select_next();
		editor.reset_cursor_blink();
	}
}

fn int get_clicked_list_index(Vec2 mouse_v, int modal_x, int modal_w, int list_y, int list_h, int row_h, int scroll_offset, int count)
{
	if (mouse_v.x >= (float)(modal_x + config::LAYOUT_METRICS.modal_padding_x) && mouse_v.x <= (float)(modal_x + modal_w - config::LAYOUT_METRICS.modal_padding_x)
		&& mouse_v.y >= (float)list_y && mouse_v.y < (float)(list_y + list_h))
	{
		int clicked_row = (int)(mouse_v.y - (float)list_y) / row_h;
		int idx = clicked_row + scroll_offset;
		if (idx >= 0 && idx < count) return idx;
	}
	return -1;
}

fn void update_editor_events(LayoutMetrics* lm, float dt, int screen_w, int height)
{
	Tab* tab = editor.active_tab();
	Document* doc = &tab.doc;

	editor.modifiers = {
		.shift = gfx::is_key_down(LEFT_SHIFT) || gfx::is_key_down(RIGHT_SHIFT),
		.ctrl  = gfx::is_key_down(LEFT_CONTROL) || gfx::is_key_down(RIGHT_CONTROL),
		.alt   = gfx::is_key_down(LEFT_ALT) || gfx::is_key_down(RIGHT_ALT)
	};

	editor.blink_timer += dt;
	if (editor.blink_timer >= config::TIMING.cursor_blink_interval)
	{
		editor.blink_timer -= config::TIMING.cursor_blink_interval;
		editor.cursor_visible = !editor.cursor_visible;
	}

	if (config::settings.file_watcher_enabled)
	{
		editor.workspace.poll_disk_changes(&editor.tabs, &editor.pending_reload_tab_index, &editor.modal.kind, dt);
	}

	if (editor.modal.kind != NONE)
	{
		if (gfx::is_key_pressed(ESCAPE))
		{
			editor.confirm_cancel_action();
			return;
		}

		Rect mrect       = editor.get_modal_rect(lm, screen_w, height);
		int modal_x      = (int)mrect.x;
		int modal_y      = (int)mrect.y;
		int modal_w      = (int)mrect.width;
		int modal_h      = (int)mrect.height;
		int input_box_h  = math::max(config::LAYOUT_METRICS.modal_input_box_h_min, lm.char_height + config::LAYOUT_METRICS.modal_input_box_padding);
		int list_y       = modal_y + 14 + lm.char_height + 8 + input_box_h + 10;
		int list_h       = modal_y + modal_h - list_y - config::LAYOUT_METRICS.modal_padding_y;
		int row_h        = math::max(config::LAYOUT_METRICS.modal_row_h_min, lm.line_height);
		int visible_rows = math::max(1, list_h / row_h);

		if (gfx::is_mouse_pressed(LEFT))
		{
			Vec2 mouse_v = gfx::get_mouse_pos();

			if (mouse_v.x < mrect.x - 4.0f || mouse_v.x > mrect.x + mrect.width + 4.0f
				|| mouse_v.y < mrect.y - 4.0f || mouse_v.y > mrect.y + mrect.height + 4.0f)
			{
				editor.confirm_cancel_action();
				return;
			}

			if (editor.modal.kind == FIND || editor.modal.kind == REPLACE)
			{
				Rect toggle_rect = editor.get_case_toggle_rect(lm, screen_w, height);
				if (mouse_v.x >= toggle_rect.x && mouse_v.x <= toggle_rect.x + toggle_rect.width
					&& mouse_v.y >= toggle_rect.y && mouse_v.y <= toggle_rect.y + toggle_rect.height)
				{
					editor.modal.search_case_sensitive = !editor.modal.search_case_sensitive;
					editor.modal.update_cached_search_matches(doc);
					editor.modal.find_from_current(doc, tab, lm.visible_lines, lm.visible_cols);
					editor.reset_cursor_blink();
					return;
				}
			}

			switch (editor.modal.kind)
			{
				case CONFIRM_CLOSE_TAB:
				case CONFIRM_EXIT:
				case CONFIRM_DISK_RELOAD:
					int btn_w = (modal_w - 32 - 24) / 3;
					int btn_h = input_box_h;
					int btn_y = modal_y + 14 + lm.char_height + 12;

					int btn1_x = modal_x + 16;
					int btn2_x = btn1_x + btn_w + 12;
					int btn3_x = btn2_x + btn_w + 12;

					if (mouse_v.y >= (float)btn_y && mouse_v.y < (float)(btn_y + btn_h))
					{
						switch
						{
							case mouse_v.x >= (float)btn1_x && mouse_v.x < (float)(btn1_x + btn_w):
								editor.confirm_save_action();
								return;
							case mouse_v.x >= (float)btn2_x && mouse_v.x < (float)(btn2_x + btn_w):
								editor.confirm_discard_action();
								return;
							case mouse_v.x >= (float)btn3_x && mouse_v.x < (float)(btn3_x + btn_w):
								editor.confirm_cancel_action();
								return;
						}
					}

				case REPLACE:
					int input1_y = modal_y + 14 + lm.char_height + 6;
					int input2_y = input1_y + input_box_h + 10;
					switch
					{
						case mouse_v.y >= (float)input1_y && mouse_v.y < (float)(input1_y + input_box_h):
							editor.modal.focus_field = 0;
							editor.reset_cursor_blink();
						case mouse_v.y >= (float)input2_y && mouse_v.y < (float)(input2_y + input_box_h):
							editor.modal.focus_field = 1;
							editor.reset_cursor_blink();
					}

				case QUICK_OPEN:
				case GLOBAL_GREP:
				case SYMBOL_OUTLINE:
					int idx = get_clicked_list_index(mouse_v, modal_x, modal_w, list_y, list_h, row_h, editor.modal.picker.scroll_offset, (int)editor.modal.picker.items.len());
					if (idx >= 0)
					{
						editor.modal.picker.selected_index = idx;
						PickerItem item = editor.modal.picker.items[(sz)idx];
						if (item.target_path.len > 0)
						{
							String resolved = resolve_path_string(item.target_path, tmem);
							if (path::is_dir((Path)resolved))
							{
								String new_query = item.target_path.ends_with("/") ? item.target_path : string::tformat("%s/", item.target_path);
								editor.modal.input.set_text(new_query);
								editor.reset_cursor_blink();
								editor.modal.update_quick_open_results(&editor.workspace);
							}
							else
							{
								editor.open_tab(resolved, true);
								if (item.line > 0)
								{
									Tab* new_tab = editor.active_tab();
									BytePos target_pos = new_tab.doc.get_pos_from_line_col(item.line - 1, math::max(0, item.col - 1));
									new_tab.doc.cursors.clear();
									new_tab.doc.cursors.push({ target_pos, target_pos, math::max(0, item.col - 1) });
									new_tab.ensure_pos_visible(target_pos, lm.visible_lines, lm.visible_cols);
								}
								editor.modal.close();
								return;
							}
						}
					}

				default: break;
			}
		}

		float modal_wheel = gfx::get_mouse_wheel();
		if (modal_wheel != 0.0f)
		{
			if (editor.modal.kind == QUICK_OPEN || editor.modal.kind == GLOBAL_GREP || editor.modal.kind == SYMBOL_OUTLINE)
			{
				editor.modal.picker.clamp_view(visible_rows);
				(modal_wheel > 0.0f) ? editor.modal.picker.select_prev() : editor.modal.picker.select_next();
			}
		}

		TextInputWidget* active_input = (editor.modal.kind == REPLACE && editor.modal.focus_field == 1)
			? &editor.modal.replace_input
			: &editor.modal.input;

		if (editor.modal.kind == FIND || editor.modal.kind == REPLACE)
		{
			if (editor.modifiers.alt && gfx::is_key_pressed(C))
			{
				editor.modal.search_case_sensitive = !editor.modal.search_case_sensitive;
				editor.modal.update_cached_search_matches(doc);
				if (editor.modal.kind == FIND || (editor.modal.kind == REPLACE && editor.modal.focus_field == 0))
				{
					editor.modal.find_from_current(doc, tab, lm.visible_lines, lm.visible_cols);
				}
			}
		}

		switch (editor.modal.kind)
		{
			case CONFIRM_CLOSE_TAB:
			case CONFIRM_EXIT:
			case CONFIRM_DISK_RELOAD:
				if (gfx::is_key_pressed(Y)) editor.confirm_save_action();
				if (gfx::is_key_pressed(N)) editor.confirm_discard_action();

			case GOTO_LINE:
				if (gfx::is_key_pressed(ENTER) || gfx::is_key_pressed(KP_ENTER))
				{
					int target         = string::to_integer{int}(editor.modal.input.view()) ?? 1;
					BytePos target_pos = doc.get_pos_from_line_col(
						math::clamp(target - 1, 0, doc.get_total_lines() - 1),
						0
					);
					doc.cursors.clear();
					doc.cursors.push({ target_pos, target_pos, 0 });
					tab.ensure_pos_visible(target_pos, lm.visible_lines, lm.visible_cols);
					editor.modal.close();
				}

			case FIND:
				if (key_pressed_or_repeat(DOWN)) editor.modal.find_next(doc, false, tab, lm.visible_lines, lm.visible_cols);
				if (key_pressed_or_repeat(UP))   editor.modal.find_next(doc, true, tab, lm.visible_lines, lm.visible_cols);
				if (gfx::is_key_pressed(ENTER) || gfx::is_key_pressed(KP_ENTER) || gfx::is_key_pressed(F3))
				{
					editor.modal.find_next(doc, editor.modifiers.shift, tab, lm.visible_lines, lm.visible_cols);
				}

			case REPLACE:
				switch
				{
					case gfx::is_key_pressed(TAB) || key_pressed_or_repeat(UP) || key_pressed_or_repeat(DOWN):
						editor.modal.focus_field = 1 - editor.modal.focus_field;
						editor.reset_cursor_blink();
					case gfx::is_key_pressed(ENTER) || gfx::is_key_pressed(KP_ENTER):
						(editor.modifiers.ctrl || editor.modifiers.alt)
							? editor.modal.replace_all(doc, tab, lm.visible_lines, lm.visible_cols)
							: editor.modal.replace_next(doc, tab, lm.visible_lines, lm.visible_cols);
					case gfx::is_key_pressed(F3):
						editor.modal.find_next(doc, editor.modifiers.shift, tab, lm.visible_lines, lm.visible_cols);
				}

			case QUICK_OPEN:
			case GLOBAL_GREP:
			case SYMBOL_OUTLINE:
				@handle_list_picker_keys(editor.modal.picker, visible_rows);
				if (gfx::is_key_pressed(ENTER) || gfx::is_key_pressed(KP_ENTER))
				{
					if (editor.modal.picker.items.len() > 0)
					{
						PickerItem item = editor.modal.picker.items[(sz)editor.modal.picker.selected_index];
						if (item.target_path.len > 0)
						{
							String resolved = resolve_path_string(item.target_path, tmem);
							if (path::is_dir((Path)resolved))
							{
								String new_query = item.target_path.ends_with("/") ? item.target_path : string::tformat("%s/", item.target_path);
								editor.modal.input.set_text(new_query);
								editor.reset_cursor_blink();
								editor.modal.update_quick_open_results(&editor.workspace);
							}
							else
							{
								editor.open_tab(resolved, true);
								if (item.line > 0)
								{
									Tab* new_tab = editor.active_tab();
									BytePos target_pos = new_tab.doc.get_pos_from_line_col(item.line - 1, math::max(0, item.col - 1));
									new_tab.doc.cursors.clear();
									new_tab.doc.cursors.push({ target_pos, target_pos, math::max(0, item.col - 1) });
									new_tab.ensure_pos_visible(target_pos, lm.visible_lines, lm.visible_cols);
								}
								editor.modal.close();
								return;
							}
						}
					}
				}

			case SAVE_AS:
				if (gfx::is_key_pressed(ENTER) || gfx::is_key_pressed(KP_ENTER))
				{
					String target_file = resolve_path_string(editor.modal.input.view(), tmem);
					if (target_file.len > 0)
					{
						file::save(target_file, (char[])doc.table.to_tstring())!!;
						if (doc.filepath.len > 0) mem::free(doc.filepath.ptr);
						doc.filepath = target_file.copy(mem);
						doc.is_file_specified = true;
						doc.is_modified = false;
						doc.last_disk_mtime = file::last_modified(doc.filepath) ?? (Time)0;
						editor.workspace.git.update(doc.filepath, doc.get_total_lines());
						editor.save_msg_timer = config::TIMING.save_msg_duration;
						editor.workspace.invalidate_files();

						PendingSaveAction action = editor.pending_action_after_save;
						editor.pending_action_after_save = NONE;

						if (editor.pending_close_tab_index >= 0)
						{
							int to_close = editor.pending_close_tab_index;
							editor.pending_close_tab_index = -1;
							editor.modal.close();
							editor.close_tab(to_close);
							return;
						}

						editor.modal.close();

						switch (action)
						{
							case RUN_FILE:     editor.run_or_compile_file(true, RUN_FILE);
							case COMPILE_FILE: editor.run_or_compile_file(false, COMPILE_FILE);
							default: break;
						}
						return;
					}
					editor.pending_action_after_save = NONE;
					editor.modal.close();
				}
			default: break;
		}

		if (key_pressed_or_repeat(LEFT))
		{
			if (active_input.cursor_pos > 0)
			{
				int prev = active_input.cursor_pos - 1;
				while (prev > 0 && (active_input.buffer[prev] & 0xC0) == 0x80) prev--;
				active_input.cursor_pos = prev;
			}
			editor.reset_cursor_blink();
		}
		if (key_pressed_or_repeat(RIGHT))
		{
			if (active_input.cursor_pos < active_input.length)
			{
				int next = active_input.cursor_pos + 1;
				while (next < active_input.length && (active_input.buffer[next] & 0xC0) == 0x80) next++;
				active_input.cursor_pos = next;
			}
			editor.reset_cursor_blink();
		}
		if (gfx::is_key_pressed(HOME))
		{
			active_input.cursor_pos = 0;
			editor.reset_cursor_blink();
		}
		if (gfx::is_key_pressed(END))
		{
			active_input.cursor_pos = active_input.length;
			editor.reset_cursor_blink();
		}

		bool input_modified = false;
		bool is_paste_event = (editor.modifiers.ctrl  && gfx::is_key_pressed(V))
			               || (editor.modifiers.shift && gfx::is_key_pressed(INSERT));

		if (is_paste_event)
		{
			String? clip_opt = gfx::get_clipboard(tmem);
			if (try clip = clip_opt)
			{
				String sanitized = clip.trim("\r\n");
				if (active_input.insert_str(sanitized)) input_modified = true;
			}
		}

		if (key_pressed_or_repeat(BACKSPACE))
		{
			if (editor.modifiers.ctrl || editor.modifiers.alt)
			{
				if (active_input.delete_word_left()) input_modified = true;
			}
			else
			{
				if (active_input.backspace()) input_modified = true;
			}
		}
		if (key_pressed_or_repeat(DELETE) && active_input.delete()) input_modified = true;

		int char_code = gfx::get_char_pressed();
		while (char_code > 0)
		{
			if (char_code >= 32 && (!editor.modifiers.ctrl || editor.modifiers.alt))
			{
				if (active_input.insert_codepoint((Char32)char_code)) input_modified = true;
			}
			char_code = gfx::get_char_pressed();
		}

		if (input_modified)
		{
			editor.reset_cursor_blink();
			if (editor.modal.kind == FIND || (editor.modal.kind == REPLACE && editor.modal.focus_field == 0))
			{
				editor.modal.update_cached_search_matches(doc);
				editor.modal.find_from_current(doc, tab, lm.visible_lines, lm.visible_cols);
			}
			if (editor.modal.kind == QUICK_OPEN) editor.modal.update_quick_open_results(&editor.workspace);
			if (editor.modal.kind == SYMBOL_OUTLINE) editor.modal.update_outline_results(doc);
			if (editor.modal.kind == GLOBAL_GREP)
			{
				editor.modal.grep_dirty = true;
				editor.modal.grep_debounce_timer = config::TIMING.grep_debounce_interval;
			}
		}

		if (editor.modal.kind == GLOBAL_GREP && editor.modal.grep_dirty)
		{
			editor.modal.grep_debounce_timer -= math::min(dt, 0.05f);
			if (editor.modal.grep_debounce_timer <= 0.0f)
			{
				editor.modal.grep_dirty = false;
				editor.modal.grep_debounce_timer = 0.0f;
				editor.modal.update_grep_results(&editor.workspace);
			}
		}
		return;
	}

	if (editor.autocomplete.is_active)
	{
		if (gfx::is_key_pressed(ESCAPE))
		{
			editor.autocomplete.is_active = false;
			return;
		}
		if (key_pressed_or_repeat(UP))
		{
			if (editor.autocomplete.selected_index > 0) editor.autocomplete.selected_index--;
			return;
		}
		if (key_pressed_or_repeat(DOWN))
		{
			if (editor.autocomplete.selected_index + 1 < (int)editor.autocomplete.items.len())
			{
				editor.autocomplete.selected_index++;
			}
			return;
		}
		if (gfx::is_key_pressed(TAB) || gfx::is_key_pressed(ENTER) || gfx::is_key_pressed(KP_ENTER))
		{
			if (editor.autocomplete.items.len() > 0)
			{
				CompletionItem item = editor.autocomplete.items[(sz)editor.autocomplete.selected_index];
				Cursor* cur = doc.primary_cursor();
				TextRange b = get_word_bounds(&doc.table, cur.pos);
				doc.table.begin_transaction(&doc.cursors);
				doc.table.replace_range(b.start, b.end, (char[])item.insert_text);
				doc.update_line_index_on_edit(b.start, b.end - b.start, (BytePos)item.insert_text.len);
				cur.pos = b.start + (BytePos)item.insert_text.len;
				cur.anchor = cur.pos;
				cur.target_col = doc.get_col(cur.pos);
				doc.table.end_transaction(&doc.cursors);
				doc.is_modified = true;
				editor.autocomplete.is_active = false;
				return;
			}
		}
	}

	Vec2 mouse_pos = gfx::get_mouse_pos();
	int tot_lines  = doc.get_total_lines();

	if (!gfx::is_mouse_down(LEFT))
	{
		if (editor.terminal.selecting)
		{
			editor.terminal.selecting = false;
			if (editor.terminal.has_selection())
			{
				String? sel_text = editor.terminal.extract_selection(tmem);
				if (try t = sel_text)
				{
					gfx::set_clipboard(t);
				}
			}
		}
		editor.mouse_down = false;
		editor.word_selecting = false;
		editor.line_selecting = false;
		editor.scrollbar_dragging = false;
		editor.minimap_dragging = false;
	}

	switch
	{
		case gfx::is_mouse_pressed(LEFT):
			if (editor.terminal.is_open && lm.terminal_height > 0)
			{
				int ty = (int)lm.terminal_rect.y;
				int th = lm.terminal_height;
				if (mouse_pos.y >= (float)ty && mouse_pos.y < (float)(ty + th))
				{
					int max_term_lines = math::max(1, (th - lm.line_height - 8) / lm.line_height);
					int total_tlines   = (int)editor.terminal.lines.len();
					int start_idx      = math::clamp(editor.terminal.scroll_line - max_term_lines + 1, 0, math::max(0, total_tlines - max_term_lines));
					int rel_ty         = (int)(mouse_pos.y - (float)(ty + lm.line_height + 8));
					int clicked_line   = start_idx + (rel_ty / lm.line_height);
					int clicked_col    = math::max(0, (int)(mouse_pos.x - 14.0f) / lm.char_width);

					editor.terminal.selecting = true;
					editor.terminal.sel_start_line = clicked_line;
					editor.terminal.sel_start_col = clicked_col;
					editor.terminal.sel_end_line = clicked_line;
					editor.terminal.sel_end_col = clicked_col;
					return;
				}
			}

			if (mouse_pos.y >= (float)(height - lm.footer_height) && mouse_pos.y <= (float)height)
			{
				String file_disp = doc.filepath.len > 0 ? doc.filepath : "untitled.c3";
				String mod_str   = doc.is_modified ? " [+]" : "";
				String save_str  = (editor.save_msg_timer > 0.0f) ? " [SAVED]" : "";
				String left_s    = string::tformat("%s%s%s", file_disp, mod_str, save_str);
				int left_w       = (int)left_s.len * lm.char_width + 24;

				if (mouse_pos.x >= 0.0f && mouse_pos.x <= (float)left_w)
				{
					editor.modal.kind = SAVE_AS;
					editor.modal.input.set_text(doc.filepath);
					editor.reset_cursor_blink();
					return;
				}
			}

			if (mouse_pos.y >= 0.0f && mouse_pos.y < (float)lm.tab_bar_height)
			{
				int tab_x       = 0;
				int close_box_w = lm.char_width * 2 + 10;
				for (sz i = 0; i < editor.tabs.len(); i++)
				{
					Tab* t  = &editor.tabs[i];
					String name_str = t.doc.filepath.file_tbasename() ?? t.doc.filepath;
					if (name_str.len == 0) name_str = "untitled.c3";

					String tab_title = string::tformat("%d: %s%s", i + 1, name_str, t.doc.is_modified ? " *" : "");
					int title_w      = (int)tab_title.len * lm.char_width;
					int tab_w        = title_w + close_box_w + config::LAYOUT_METRICS.tab_extra_padding;

					if (tab_x + tab_w > screen_w - config::LAYOUT_METRICS.tab_min_w_gap) tab_w = screen_w - config::LAYOUT_METRICS.tab_min_w_gap - tab_x;
					if (tab_w <= close_box_w + 10) break;

					if (mouse_pos.x >= (float)tab_x && mouse_pos.x < (float)(tab_x + tab_w))
					{
						if (mouse_pos.x >= (float)(tab_x + tab_w - close_box_w))
						{
							editor.request_close_tab((int)i);
						}
						else
						{
							editor.active_tab_index = (int)i;
							editor.reset_cursor_blink();
						}
						return;
					}
					tab_x += tab_w;
				}
				return;
			}

			if (tot_lines > lm.visible_lines && mouse_pos.x >= lm.scrollbar_rect.x - 4.0f
				&& mouse_pos.x <= (float)screen_w
				&& mouse_pos.y >= lm.scrollbar_rect.y
				&& mouse_pos.y <= (float)(lm.scrollbar_rect.y + lm.scrollbar_rect.height))
			{
				float max_scroll   = (float)(tot_lines - lm.visible_lines);
				float track_h      = lm.scrollbar_rect.height;
				float thumb_h      = math::max(config::LAYOUT_METRICS.scrollbar_min_thumb_h, track_h * (float)lm.visible_lines / (float)tot_lines);
				float scrollable_h = track_h - thumb_h;
				float thumb_y      = lm.scrollbar_rect.y + (scrollable_h * (float)tab.scroll_line / max_scroll);

				editor.scrollbar_dragging = true;
				editor.minimap_dragging = false;
				editor.mouse_down = false;
				if (mouse_pos.y >= thumb_y && mouse_pos.y <= thumb_y + thumb_h)
				{
					editor.scrollbar_drag_offset_y = mouse_pos.y - thumb_y;
				}
				else
				{
					editor.scrollbar_drag_offset_y = thumb_h * 0.5f;
					float new_thumb_y = mouse_pos.y - editor.scrollbar_drag_offset_y;
					float norm        = scrollable_h > 0.0f ? (new_thumb_y - lm.scrollbar_rect.y) / scrollable_h : 0.0f;
					tab.scroll_line = math::clamp((int)math::round(norm * max_scroll), 0, (int)max_scroll);
				}
				editor.reset_cursor_blink();
				break;
			}

			if (config::settings.show_minimap && lm.minimap_w > 0
				&& mouse_pos.x >= lm.minimap_rect.x
				&& mouse_pos.x <= lm.minimap_rect.x + lm.minimap_rect.width
				&& mouse_pos.y >= lm.minimap_rect.y
				&& mouse_pos.y <= lm.minimap_rect.y + lm.minimap_rect.height)
			{
				float mm_y = lm.minimap_rect.y;
				float mm_h = lm.minimap_rect.height;
				int max_scroll = math::max(0, tot_lines - lm.visible_lines);
				float click_rel_y = mouse_pos.y - mm_y;
				float norm = mm_h > 0.0f ? click_rel_y / mm_h : 0.0f;

				editor.minimap_dragging = true;
				editor.scrollbar_dragging = false;
				editor.mouse_down = false;
				editor.minimap_drag_offset_y = 0.0f;
				tab.scroll_line = math::clamp((int)math::round(norm * (float)max_scroll), 0, max_scroll);
				editor.reset_cursor_blink();
				break;
			}

			editor.scrollbar_dragging = false;
			editor.minimap_dragging = false;
			editor.mouse_down = true;
			double now = gfx::get_time();

			int rel_y = (int)(mouse_pos.y - (float)lm.text_start_y);
			int line  = rel_y / lm.line_height + tab.scroll_line;
			int rel_x = (int)(mouse_pos.x - (float)lm.text_start_x + (float)lm.char_width * 0.5f);
			int col   = math::max(0, rel_x / lm.char_width + tab.scroll_col);
			BytePos clicked_pos = doc.get_pos_from_line_col(line, col);

			float dx = mouse_pos.x - editor.last_click_pos.x;
			float dy = mouse_pos.y - editor.last_click_pos.y;

			if (now - editor.last_click_time < config::TIMING.double_click_threshold && (dx * dx + dy * dy) < config::TIMING.double_click_dist_sq)
			{
				editor.click_count = (editor.click_count % 3) + 1;
			}
			else
			{
				editor.click_count = 1;
			}
			editor.last_click_time = now;
			editor.last_click_pos = mouse_pos;

			Cursor* cur = doc.primary_cursor();
			switch (editor.click_count)
			{
				case 1:
					editor.word_selecting = false;
					editor.line_selecting = false;
					cur.pos = clicked_pos;
					if (!editor.modifiers.shift) cur.anchor = cur.pos;
					cur.target_col = doc.get_col(cur.pos);

				case 2:
					editor.word_selecting = true;
					editor.line_selecting = false;
					TextRange bounds = get_word_bounds(&doc.table, clicked_pos);
					editor.word_sel_anchor_start = bounds.start;
					editor.word_sel_anchor_end = bounds.end;
					cur.anchor = bounds.start;
					cur.pos = bounds.end;
					cur.target_col = doc.get_col(cur.pos);

				case 3:
					editor.word_selecting = false;
					editor.line_selecting = true;
					int clicked_line = doc.get_line(clicked_pos);
					BytePos l_start = doc.get_line_start_of_line(clicked_line);
					BytePos l_end = (clicked_line + 1 < doc.get_total_lines())
						? doc.get_line_start_of_line(clicked_line + 1)
						: doc.get_line_end(l_start);

					editor.word_sel_anchor_start = l_start;
					editor.word_sel_anchor_end = l_end;
					cur.anchor = l_start;
					cur.pos = l_end;
					cur.target_col = doc.get_col(cur.pos);
			}

			if (!editor.modifiers.shift && !editor.modifiers.alt && doc.cursors.len() > 1)
			{
				Cursor single = *cur;
				doc.cursors.clear();
				doc.cursors.push(single);
			}
			editor.reset_cursor_blink();

		case editor.terminal.selecting && gfx::is_mouse_down(LEFT):
			if (editor.terminal.is_open && lm.terminal_height > 0)
			{
				int ty = (int)lm.terminal_rect.y;
				int th = lm.terminal_height;
				int max_term_lines = math::max(1, (th - lm.line_height - 8) / lm.line_height);
				int total_tlines   = (int)editor.terminal.lines.len();
				int start_idx      = math::clamp(editor.terminal.scroll_line - max_term_lines + 1, 0, math::max(0, total_tlines - max_term_lines));
				int rel_ty         = (int)(mouse_pos.y - (float)(ty + lm.line_height + 8));
				int drag_line      = start_idx + (rel_ty / lm.line_height);
				int drag_col       = math::max(0, (int)(mouse_pos.x - 14.0f) / lm.char_width);

				editor.terminal.sel_end_line = drag_line;
				editor.terminal.sel_end_col = drag_col;
			}

		case editor.scrollbar_dragging && gfx::is_mouse_down(LEFT):
			if (tot_lines > lm.visible_lines)
			{
				float max_scroll   = (float)(tot_lines - lm.visible_lines);
				float track_h      = lm.scrollbar_rect.height;
				float thumb_h      = math::max(config::LAYOUT_METRICS.scrollbar_min_thumb_h, track_h * (float)lm.visible_lines / (float)tot_lines);
				float scrollable_h = track_h - thumb_h;
				float new_thumb_y  = mouse_pos.y - editor.scrollbar_drag_offset_y;
				float norm         = scrollable_h > 0.0f ? (new_thumb_y - lm.scrollbar_rect.y) / scrollable_h : 0.0f;
				tab.scroll_line = math::clamp((int)math::round(norm * max_scroll), 0, (int)max_scroll);
				editor.reset_cursor_blink();
			}

		case editor.minimap_dragging && gfx::is_mouse_down(LEFT):
			if (tot_lines > lm.visible_lines)
			{
				float mm_y = lm.minimap_rect.y;
				float mm_h = lm.minimap_rect.height;
				int max_scroll = math::max(0, tot_lines - lm.visible_lines);
				float click_rel_y = mouse_pos.y - mm_y;
				float norm = mm_h > 0.0f ? click_rel_y / mm_h : 0.0f;
				tab.scroll_line = math::clamp((int)math::round(norm * (float)max_scroll), 0, max_scroll);
				editor.reset_cursor_blink();
			}

		case editor.mouse_down && gfx::is_mouse_down(LEFT):
			int rel_y = (int)(mouse_pos.y - (float)lm.text_start_y);
			int line  = rel_y / lm.line_height + tab.scroll_line;
			int rel_x = (int)(mouse_pos.x - (float)lm.text_start_x + (float)lm.char_width * 0.5f);
			int col   = math::max(0, rel_x / lm.char_width + tab.scroll_col);
			BytePos cur_pos = doc.get_pos_from_line_col(line, col);

			Cursor* cur_p = doc.primary_cursor();
			if (editor.line_selecting)
			{
				int drag_line = doc.get_line(cur_pos);
				BytePos drag_l_start = doc.get_line_start_of_line(drag_line);
				BytePos drag_l_end = (drag_line + 1 < doc.get_total_lines())
					? doc.get_line_start_of_line(drag_line + 1)
					: doc.get_line_end(drag_l_start);

				if (cur_pos >= editor.word_sel_anchor_start)
				{
					cur_p.anchor = editor.word_sel_anchor_start;
					cur_p.pos = drag_l_end;
				}
				else
				{
					cur_p.anchor = editor.word_sel_anchor_end;
					cur_p.pos = drag_l_start;
				}
			}
			else if (editor.word_selecting)
			{
				TextRange cur_bounds = get_word_bounds(&doc.table, cur_pos);
				if (cur_pos >= editor.word_sel_anchor_start)
				{
					cur_p.anchor = editor.word_sel_anchor_start;
					cur_p.pos = cur_bounds.end;
				}
				else
				{
					cur_p.anchor = editor.word_sel_anchor_end;
					cur_p.pos = cur_bounds.start;
				}
			}
			else
			{
				cur_p.pos = cur_pos;
			}
			cur_p.target_col = doc.get_col(cur_p.pos);
			editor.reset_cursor_blink();

		case gfx::is_mouse_released(LEFT):
			if (editor.terminal.selecting)
			{
				editor.terminal.selecting = false;
				if (editor.terminal.has_selection())
				{
					String? sel_text = editor.terminal.extract_selection(tmem);
					if (try t = sel_text)
					{
						gfx::set_clipboard(t);
					}
				}
			}
			editor.mouse_down = false;
			editor.word_selecting = false;
			editor.line_selecting = false;
			editor.scrollbar_dragging = false;
			editor.minimap_dragging = false;
	}

	float wheel = gfx::get_mouse_wheel();
	if (wheel != 0.0f)
	{
		if (editor.terminal.is_open && lm.terminal_height > 0)
		{
			int ty = (int)lm.terminal_rect.y;
			int th = lm.terminal_height;
			if (mouse_pos.y >= (float)ty && mouse_pos.y < (float)(ty + th))
			{
				int total_tlines = (int)editor.terminal.lines.len();
				editor.terminal.scroll_line = math::clamp(editor.terminal.scroll_line - (int)wheel * config::LAYOUT_METRICS.scroll_wheel_lines, 0, math::max(0, total_tlines - 1));
				editor.terminal.auto_scroll = (editor.terminal.scroll_line >= total_tlines - 1);
				return;
			}
		}

		switch
		{
			case editor.modifiers.ctrl:
				editor.font_scale = math::clamp(editor.font_scale + (wheel > 0.0f ? config::LAYOUT_METRICS.font_zoom_step : -config::LAYOUT_METRICS.font_zoom_step), config::LAYOUT_METRICS.min_font_scale, config::LAYOUT_METRICS.max_font_scale);
			case editor.modifiers.shift:
				tab.scroll_col = math::max(0, tab.scroll_col - (int)wheel * config::LAYOUT_METRICS.scroll_wheel_cols);
			default:
				tab.scroll_line = math::clamp(tab.scroll_line - (int)wheel * config::LAYOUT_METRICS.scroll_wheel_lines, 0, math::max(0, tot_lines - 1));
		}
		editor.reset_cursor_blink();
	}

	bool page_held = gfx::is_key_down(PAGE_UP) || gfx::is_key_down(PAGE_DOWN);
	editor.page_hold_timer = page_held ? editor.page_hold_timer + dt : 0.0f;

	for (int k = 32; k < 349; k++)
	{
		Key key = (Key)k;
		bool is_triggered = false;
		switch (key)
		{
			case LEFT:
			case RIGHT:
			case UP:
			case DOWN:
			case PAGE_UP:
			case PAGE_DOWN:
			case HOME:
			case END:
			case BACKSPACE:
			case DELETE:
			case ENTER:
			case KP_ENTER:
			case TAB:
				is_triggered = key_pressed_or_repeat(key);
			default:
				switch
				{
					case editor.modifiers.ctrl && (key == Z || key == Y || key == D || key == R || key == SPACE):
					case editor.modifiers.alt && (key == UP || key == DOWN || key == C):
						is_triggered = key_pressed_or_repeat(key);
					default:
						is_triggered = gfx::is_key_pressed(key);
				}
		}
		if (is_triggered)
		{
			EditorCommand cmd = config::resolve_key_command(key, editor.modifiers);
			if (cmd != CMD_NONE) editor.dispatch_command(cmd, lm, dt);
		}
	}

	int cp = gfx::get_char_pressed();
	while (cp > 0)
	{
		if (cp >= 32 && (!editor.modifiers.ctrl || editor.modifiers.alt))
		{
			doc.insert_codepoint((Char32)cp);
			tab.ensure_cursor_visible(lm.visible_lines, lm.visible_cols);

			if (config::settings.autocomplete_enabled)
			{
				BytePos p = doc.cursors[0].pos;
				bool is_dot = (cp == '.');
				bool is_colon = (cp == ':' && p > 1 && doc.table.char_at(p - 2) == ':');

				TextRange b = get_word_bounds(&doc.table, p);
				String pre = doc.table.get_slice(b.start, p, tmem);

				String parent_target = "";
				if (is_dot && p > 1)
				{
					TextRange pb = get_word_bounds(&doc.table, p - 2);
					parent_target = doc.table.get_slice(pb.start, pb.end, tmem);
				}
				else if (is_colon && p > 2)
				{
					TextRange pb = get_word_bounds(&doc.table, p - 3);
					parent_target = doc.table.get_slice(pb.start, pb.end, tmem);
				}
				else if (b.start > 0 && doc.table.char_at(b.start - 1) == '.')
				{
					is_dot = true;
					TextRange pb = get_word_bounds(&doc.table, b.start - 1);
					parent_target = doc.table.get_slice(pb.start, pb.end, tmem);
				}

				bool is_two_caps = (pre.len >= 2 && pre[0].is_upper() && pre[1].is_upper());
				bool is_camel = (pre.len >= 2 && pre[0].is_upper() && pre[1].is_lower());

				if (is_dot || is_colon || is_two_caps || is_camel || pre.len >= 3)
				{
					editor.autocomplete.collect_suggestions(
						editor.workspace.lsp.symbols.array_view(),
						&doc.table,
						p,
						pre,
						is_dot,
						is_colon,
						parent_target
					);
				}
				else
				{
					editor.autocomplete.is_active = false;
				}
			}
		}
		cp = gfx::get_char_pressed();
	}
}

fn void update_draw_frame() => @pool()
{
	font::init_font_texture();
	float dt     = gfx::get_frame_time();
	int screen_w = gfx::get_screen_width();
	int height   = gfx::get_screen_height();
	if (screen_w <= 0) screen_w = 1600;
	if (height <= 0) height = 900;

	if (editor.save_msg_timer > 0.0f)
	{
		editor.save_msg_timer -= dt;
		if (editor.save_msg_timer < 0.0f) editor.save_msg_timer = 0.0f;
	}

	if (!editor.initialized)
	{
		editor.init(current_workspace);
	}

	Tab* tab                = editor.active_tab();
	BytePos prev_cursor_pos = tab.doc.primary_cursor().pos;
	BytePos prev_table_len  = tab.doc.table.len();

	LayoutMetrics lm = ui::compute_layout(
		screen_w,
		height,
		editor.font_scale,
		tab.doc.get_total_lines(),
		true,
		editor.terminal.is_open,
		editor.terminal.height_px
	);
	update_editor_events(&lm, dt, screen_w, height);

	tab = editor.active_tab();
	if (tab.doc.primary_cursor().pos != prev_cursor_pos || tab.doc.table.len() != prev_table_len)
	{
		editor.reset_cursor_blink();
	}

	ui::render(&editor, screen_w, height, &lm);
}

fn int main(String[] args) @winmain
{
	String target_dir = "";
	List{String} files_to_open;
	files_to_open.tinit(args.len);

	if (args.len > 1)
	{
		for (sz i = 1; i < args.len; i++)
		{
			String arg = args[i];
			if (path::is_dir((Path)arg))
			{
				if (target_dir.len == 0) target_dir = arg;
			}
			else
			{
				files_to_open.push(arg);
			}
		}
	}

	if (target_dir.len > 0)
	{
		(void)path::chdir((Path)target_dir);
	}

	Path? cwd = path::cwd(mem);
	if (try cwd_path = cwd)
	{
		current_workspace = (String)cwd_path;
	}
	else
	{
		current_workspace = target_dir.len > 0 ? target_dir.copy(mem) : ".";
	}

	editor.init(current_workspace);

	if (files_to_open.len() > 0)
	{
		foreach (filepath : files_to_open)
		{
			editor.open_tab(filepath, true);
		}
		editor.active_tab_index = 0;
	}
	else
	{
		bool session_restored = editor.load_session(current_workspace);
		if (!session_restored)
		{
			editor.open_tab(
				"untitled.c3",
				false,
`/* c3ed - Quick Reference

    Ctrl+O / Ctrl+P      Quick open file / path navigator
    Ctrl+Shift+F         Workspace grep search
    Ctrl+Shift+R         Document symbol outline
    F1                   Go to definition (WIP)
    Ctrl+G               Go to line

    Ctrl+F / Ctrl+H      Find / Replace in file
    Alt+C                Toggle case sensitivity

    F5                   Run project (c3c run)
    Ctrl+F5              Run current file (c3c compile-run)
    Ctrl+Shift+B         Build project (c3c build)
    Ctrl+~               Toggle output / terminal panel

    Ctrl+Shift+Up/Down   Column multi-cursor
    Ctrl+D               Select next occurrence
    Ctrl+/               Toggle line comment
    Ctrl+Shift+D         Duplicate line
*/

module main;
import std;

fn int main(String[] args)
{
	io::printn("Hello from c3ed!");
	return 0;
}
`
			);
		}
	}

	gfx::init_window(1024, 600, "C3 Text Editor");

	$if env::WASM:
		emscripten_set_main_loop(&update_draw_frame, 60, 1);
	$else
		while (!editor.should_exit)
		{
			if (gfx::should_close())
			{
				bool any_modified = false;
				foreach (&t : editor.tabs)
				{
					if (t.doc.is_modified)
					{
						any_modified = true;
						break;
					}
				}
				if (any_modified)
				{
					editor.modal.kind = CONFIRM_EXIT;
					editor.reset_cursor_blink();
				}
				else
				{
					editor.should_exit = true;
				}
			}
			update_draw_frame();
		}

		editor.save_session(current_workspace);
		editor.free();
		gfx::close_window();
	$endif

	return 0;
}

alias EmCallbackFunc = fn void();
extern fn void emscripten_set_main_loop(EmCallbackFunc func, int fps, int simulate_infinite_loop) @feat(WASM);