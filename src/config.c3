module c3ed::config;
import std, c3ed::gfx;

alias Color = char[<4>];

struct Theme
{
	Color bg;
	Color header_bg;
	Color tab_bg;
	Color tab_active_bg;
	Color tab_border;
	Color footer_bg;
	Color gutter_bg;
	Color gutter_border;
	Color line_highlight;
	Color text;
	Color text_bright;
	Color text_muted;
	Color tab_guide;
	Color indent_guide;
	Color indent_guide_active;
	Color header_muted;
	Color accent_blue;
	Color accent_green;
	Color accent_yellow;
	Color accent_red;
	Color selection_bg;
	Color cursor;
	Color scrollbar;
	Color scrollbar_act;
	Color git_added;
	Color git_modified;
	Color git_deleted;
	Color squiggle_error;
	Color squiggle_warn;
	Color minimap_bg;
	Color minimap_viewport;
	Color panel_bg;
	Color popup_bg;
	Color popup_border;
	Color popup_selected;
}

const Theme DEFAULT_THEME = {
	.bg                  = { 15, 23, 42, 255 },
	.header_bg           = { 30, 41, 59, 255 },
	.tab_bg              = { 20, 29, 47, 255 },
	.tab_active_bg       = { 15, 23, 42, 255 },
	.tab_border          = { 51, 65, 85, 255 },
	.footer_bg           = { 30, 41, 59, 255 },
	.gutter_bg           = { 15, 23, 42, 255 },
	.gutter_border       = { 51, 65, 85, 255 },
	.line_highlight      = { 30, 41, 59, 160 },
	.text                = { 226, 232, 240, 255 },
	.text_bright         = { 248, 250, 252, 255 },
	.text_muted          = { 100, 116, 139, 255 },
	.tab_guide           = { 71, 85, 105, 65 },
	.indent_guide        = { 51, 65, 85, 90 },
	.indent_guide_active = { 56, 189, 248, 180 },
	.header_muted        = { 148, 163, 184, 255 },
	.accent_blue         = { 56, 189, 248, 255 },
	.accent_green        = { 74, 222, 128, 255 },
	.accent_yellow       = { 250, 204, 21, 255 },
	.accent_red          = { 248, 113, 113, 255 },
	.selection_bg        = { 3, 105, 161, 255 },
	.cursor              = { 56, 189, 248, 255 },
	.scrollbar           = { 71, 85, 105, 180 },
	.scrollbar_act       = { 56, 189, 248, 220 },
	.git_added           = { 74, 222, 128, 255 },
	.git_modified        = { 250, 204, 21, 255 },
	.git_deleted         = { 248, 113, 113, 255 },
	.squiggle_error      = { 248, 113, 113, 230 },
	.squiggle_warn       = { 250, 204, 21, 230 },
	.minimap_bg          = { 10, 16, 30, 200 },
	.minimap_viewport    = { 56, 189, 248, 35 },
	.panel_bg            = { 12, 18, 34, 255 },
	.popup_bg            = { 24, 33, 52, 255 },
	.popup_border        = { 56, 189, 248, 200 },
	.popup_selected      = { 3, 105, 161, 220 }
};

struct LayoutMetricsConfig
{
	int gutter_padding_right;
	int gutter_border_w;
	int gutter_base_margin;
	int gutter_min_digits;
	int text_padding_x;
	int text_padding_y;
	int scrollbar_w;
	float scrollbar_min_thumb_h;
	int minimap_margin_right;
	int minimap_line_h;
	int minimap_min_thumb_h;
	float min_font_scale;
	float max_font_scale;
	float font_zoom_step;
	int scroll_wheel_lines;
	int scroll_wheel_cols;
	int modal_min_w;
	int modal_wide_min_w;
	int modal_list_h;
	int modal_input_box_h_min;
	int modal_input_box_padding;
	int modal_padding_x;
	int modal_padding_y;
	int modal_row_h_min;
	int terminal_min_h;
	int terminal_default_h;
	int popup_w;
	int popup_max_rows;
	int tab_min_w_gap;
	int tab_extra_padding;
}

const LayoutMetricsConfig LAYOUT_METRICS = {
	.gutter_padding_right    = 8,
	.gutter_border_w         = 2,
	.gutter_base_margin      = 10,
	.gutter_min_digits       = 4,
	.text_padding_x          = 8,
	.text_padding_y          = 6,
	.scrollbar_w             = 10,
	.scrollbar_min_thumb_h   = 20.0f,
	.minimap_margin_right    = 14,
	.minimap_line_h          = 2,
	.minimap_min_thumb_h     = 16,
	.min_font_scale          = 0.4f,
	.max_font_scale          = 4.0f,
	.font_zoom_step          = 0.1f,
	.scroll_wheel_lines      = 3,
	.scroll_wheel_cols       = 7,
	.modal_min_w             = 560,
	.modal_wide_min_w        = 760,
	.modal_list_h            = 420,
	.modal_input_box_h_min   = 28,
	.modal_input_box_padding = 12,
	.modal_padding_x         = 16,
	.modal_padding_y         = 14,
	.modal_row_h_min         = 24,
	.terminal_min_h          = 100,
	.terminal_default_h      = 220,
	.popup_w                 = 320,
	.popup_max_rows          = 8,
	.tab_min_w_gap           = 40,
	.tab_extra_padding       = 16
};

struct TimingConfig
{
	float cursor_blink_interval;
	double double_click_threshold;
	float double_click_dist_sq;
	float grep_debounce_interval;
	float save_msg_duration;
	float file_watcher_interval;
	float page_hold_multiplier;
	int max_page_speed;
}

const TimingConfig TIMING = {
	.cursor_blink_interval = 0.5f,
	.double_click_threshold = 0.35,
	.double_click_dist_sq   = 100.0f,
	.grep_debounce_interval = 0.18f,
	.save_msg_duration      = 2.0f,
	.file_watcher_interval  = 1.0f,
	.page_hold_multiplier   = 5.0f,
	.max_page_speed         = 10
};

struct EditorSettings
{
	int tab_size;
	bool use_spaces_for_tab;
	bool show_indent_guides;
	bool highlight_matching_brackets;
	bool show_git_gutter;
	bool show_minimap;
	int minimap_width;
	bool autocomplete_enabled;
	bool auto_close_brackets;
	bool format_on_save;
	bool file_watcher_enabled;
	float font_scale;
}

const EditorSettings DEFAULT_SETTINGS = {
	.tab_size                    = 4,
	.use_spaces_for_tab          = false,
	.show_indent_guides          = true,
	.highlight_matching_brackets = true,
	.show_git_gutter             = true,
	.show_minimap                = true,
	.minimap_width               = 68,
	.autocomplete_enabled        = true,
	.auto_close_brackets         = true,
	.format_on_save              = false,
	.file_watcher_enabled        = true,
	.font_scale                  = 1.0f
};

EditorSettings settings = DEFAULT_SETTINGS;
Theme theme = DEFAULT_THEME;

enum EditorCommand
{
	CMD_NONE,
	CMD_MOVE_LEFT,
	CMD_MOVE_RIGHT,
	CMD_MOVE_UP,
	CMD_MOVE_DOWN,
	CMD_MOVE_WORD_LEFT,
	CMD_MOVE_WORD_RIGHT,
	CMD_MOVE_LINE_START,
	CMD_MOVE_LINE_END,
	CMD_MOVE_FILE_START,
	CMD_MOVE_FILE_END,
	CMD_PAGE_UP,
	CMD_PAGE_DOWN,
	CMD_JUMP_MATCHING_BRACKET,
	CMD_ADD_CURSOR_ABOVE,
	CMD_ADD_CURSOR_BELOW,
	CMD_ADD_NEXT_OCCURRENCE,
	CMD_SELECT_ALL,
	CMD_SELECT_TO_TOP,
	CMD_SELECT_TO_BOTTOM,
	CMD_CLEAR_SELECTION,
	CMD_INSERT_TAB,
	CMD_INDENT,
	CMD_OUTDENT,
	CMD_BACKSPACE,
	CMD_DELETE,
	CMD_DELETE_WORD_LEFT,
	CMD_DELETE_WORD_RIGHT,
	CMD_ENTER,
	CMD_DUPLICATE_LINE,
	CMD_DELETE_LINE,
	CMD_MOVE_LINE_UP,
	CMD_MOVE_LINE_DOWN,
	CMD_TOGGLE_COMMENT,
	CMD_TO_UPPERCASE,
	CMD_TO_LOWERCASE,
	CMD_COPY,
	CMD_CUT,
	CMD_PASTE,
	CMD_UNDO,
	CMD_REDO,
	CMD_OPEN_FIND,
	CMD_OPEN_REPLACE,
	CMD_FIND_NEXT,
	CMD_FIND_PREV,
	CMD_REPLACE_NEXT,
	CMD_REPLACE_ALL,
	CMD_TOGGLE_CASE_SENSITIVITY,
	CMD_OPEN_QUICK_OPEN,
	CMD_OPEN_GLOBAL_GREP,
	CMD_OPEN_GOTO_LINE,
	CMD_OPEN_SYMBOL_OUTLINE,
	CMD_GOTO_NEXT_SYMBOL,
	CMD_GOTO_DEFINITION,
	CMD_TRIGGER_AUTOCOMPLETE,
	CMD_BUILD_PROJECT,
	CMD_COMPILE_THIS_FILE,
	CMD_RUN_PROJECT,
	CMD_RUN_THIS_FILE,
	CMD_TOGGLE_TERMINAL,
	CMD_NEW_TAB,
	CMD_CLOSE_TAB,
	CMD_NEXT_TAB,
	CMD_PREV_TAB,
	CMD_TAB_1,
	CMD_TAB_2,
	CMD_TAB_3,
	CMD_TAB_4,
	CMD_TAB_5,
	CMD_TAB_6,
	CMD_TAB_7,
	CMD_TAB_8,
	CMD_TAB_9,
	CMD_SAVE_FILE,
	CMD_SAVE_AS,
	CMD_QUIT,
	CMD_ZOOM_IN,
	CMD_ZOOM_OUT
}

bitstruct KeyModifiers : uint
{
	bool shift;
	bool ctrl;
	bool alt;
}

struct KeyBinding
{
	EditorCommand command;
	Key key;
	KeyModifiers mods;
}

const KeyBinding[*] KEYBINDINGS = {
	{ CMD_NEW_TAB, T, { .ctrl } },
	{ CMD_CLOSE_TAB, W, { .ctrl } },
	{ CMD_NEXT_TAB, TAB, { .ctrl } },
	{ CMD_PREV_TAB, TAB, { .ctrl, .shift } },
	{ CMD_TAB_1, ONE, { .alt } },
	{ CMD_TAB_2, TWO, { .alt } },
	{ CMD_TAB_3, THREE, { .alt } },
	{ CMD_TAB_4, FOUR, { .alt } },
	{ CMD_TAB_5, FIVE, { .alt } },
	{ CMD_TAB_6, SIX, { .alt } },
	{ CMD_TAB_7, SEVEN, { .alt } },
	{ CMD_TAB_8, EIGHT, { .alt } },
	{ CMD_TAB_9, NINE, { .alt } },
	{ CMD_BUILD_PROJECT, B, { .ctrl, .shift } },
	{ CMD_COMPILE_THIS_FILE, F5, { .ctrl, .shift } },
	{ CMD_RUN_PROJECT, F5, { } },
	{ CMD_RUN_THIS_FILE, F5, { .ctrl } },
	{ CMD_TOGGLE_TERMINAL, GRAVE, { .ctrl } },
	{ CMD_SAVE_FILE, S, { .ctrl } },
	{ CMD_SAVE_AS, S, { .ctrl, .shift } },
	{ CMD_QUIT, Q, { .ctrl } },
	{ CMD_OPEN_FIND, F, { .ctrl } },
	{ CMD_OPEN_REPLACE, H, { .ctrl } },
	{ CMD_TOGGLE_CASE_SENSITIVITY, C, { .alt } },
	{ CMD_OPEN_GLOBAL_GREP, F, { .ctrl, .shift } },
	{ CMD_OPEN_QUICK_OPEN, O, { .ctrl } },
	{ CMD_OPEN_QUICK_OPEN, P, { .ctrl } },
	{ CMD_OPEN_GOTO_LINE, G, { .ctrl } },
	{ CMD_GOTO_NEXT_SYMBOL, R, { .ctrl } },
	{ CMD_OPEN_SYMBOL_OUTLINE, R, { .ctrl, .shift } },
	{ CMD_FIND_NEXT, F3, { } },
	{ CMD_FIND_PREV, F3, { .shift } },
	{ CMD_GOTO_DEFINITION, F1, { } },
	{ CMD_TRIGGER_AUTOCOMPLETE, SPACE, { .ctrl } },
	{ CMD_UNDO, Z, { .ctrl } },
	{ CMD_REDO, Y, { .ctrl } },
	{ CMD_REDO, Z, { .ctrl, .shift } },
	{ CMD_COPY, C, { .ctrl } },
	{ CMD_CUT, X, { .ctrl } },
	{ CMD_PASTE, V, { .ctrl } },
	{ CMD_PASTE, INSERT, { .shift } },
	{ CMD_SELECT_ALL, A, { .ctrl } },
	{ CMD_ADD_NEXT_OCCURRENCE, D, { .ctrl } },
	{ CMD_ADD_CURSOR_ABOVE, UP, { .ctrl, .shift } },
	{ CMD_ADD_CURSOR_BELOW, DOWN, { .ctrl, .shift } },
	{ CMD_DUPLICATE_LINE, D, { .ctrl, .shift } },
	{ CMD_DELETE_LINE, K, { .ctrl, .shift } },
	{ CMD_TOGGLE_COMMENT, SLASH, { .ctrl } },
	{ CMD_TOGGLE_COMMENT, M, { .ctrl } },
	{ CMD_TO_LOWERCASE, U, { .ctrl } },
	{ CMD_TO_UPPERCASE, U, { .ctrl, .shift } },
	{ CMD_JUMP_MATCHING_BRACKET, B, { .ctrl } },
	{ CMD_JUMP_MATCHING_BRACKET, BACKSLASH, { .ctrl, .shift } },
	{ CMD_MOVE_LINE_UP, UP, { .alt } },
	{ CMD_MOVE_LINE_DOWN, DOWN, { .alt } },
	{ CMD_SELECT_TO_TOP, HOME, { .ctrl, .shift } },
	{ CMD_SELECT_TO_BOTTOM, END, { .ctrl, .shift } },
	{ CMD_MOVE_FILE_START, HOME, { .ctrl } },
	{ CMD_MOVE_FILE_END, END, { .ctrl } },
	{ CMD_MOVE_WORD_LEFT, LEFT, { .ctrl } },
	{ CMD_MOVE_WORD_RIGHT, RIGHT, { .ctrl } },
	{ CMD_DELETE_WORD_LEFT, BACKSPACE, { .ctrl } },
	{ CMD_DELETE_WORD_RIGHT, DELETE, { .ctrl } },
	{ CMD_MOVE_LEFT, LEFT, { } },
	{ CMD_MOVE_RIGHT, RIGHT, { } },
	{ CMD_MOVE_UP, UP, { } },
	{ CMD_MOVE_DOWN, DOWN, { } },
	{ CMD_MOVE_LINE_START, HOME, { } },
	{ CMD_MOVE_LINE_END, END, { } },
	{ CMD_PAGE_UP, PAGE_UP, { } },
	{ CMD_PAGE_DOWN, PAGE_DOWN, { } },
	{ CMD_BACKSPACE, BACKSPACE, { } },
	{ CMD_DELETE, DELETE, { } },
	{ CMD_ENTER, ENTER, { } },
	{ CMD_ENTER, KP_ENTER, { } },
	{ CMD_INSERT_TAB, TAB, { } },
	{ CMD_OUTDENT, TAB, { .shift } },
	{ CMD_CLEAR_SELECTION, ESCAPE, { } },
	{ CMD_ZOOM_IN, EQUAL, { .ctrl } },
	{ CMD_ZOOM_IN, KP_ADD, { .ctrl } },
	{ CMD_ZOOM_OUT, MINUS, { .ctrl } },
	{ CMD_ZOOM_OUT, KP_SUBTRACT, { .ctrl } }
};

fn EditorCommand resolve_key_command(Key key, KeyModifiers mods)
{
	foreach (&binding : KEYBINDINGS)
	{
		if (binding.key == key && (uint)binding.mods == (uint)mods)
		{
			return binding.command;
		}
	}

	if (mods.shift)
	{
		KeyModifiers no_shift = mods;
		no_shift.shift = false;
		foreach (&binding : KEYBINDINGS)
		{
			if (binding.key == key && (uint)binding.mods == (uint)no_shift)
			{
				switch (binding.command)
				{
					case CMD_MOVE_LEFT:
					case CMD_MOVE_RIGHT:
					case CMD_MOVE_UP:
					case CMD_MOVE_DOWN:
					case CMD_MOVE_WORD_LEFT:
					case CMD_MOVE_WORD_RIGHT:
					case CMD_MOVE_LINE_START:
					case CMD_MOVE_LINE_END:
					case CMD_PAGE_UP:
					case CMD_PAGE_DOWN:
					case CMD_DELETE_WORD_LEFT:
					case CMD_DELETE_WORD_RIGHT:
					case CMD_BACKSPACE:
					case CMD_DELETE:
					case CMD_ENTER:
						return binding.command;
					default: break;
				}
			}
		}
	}
	return CMD_NONE;
}
