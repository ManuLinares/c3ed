module c3ed::gfx;
import std, raylib6, c3ed::config;

// --- Fast Window Initialization Stubs for Linux/POSIX ---
// Bypasses GLFW's slow `/dev/input/event*` joystick probing on startup
fn bool _glfwInitJoysticksLinux() @cname("_glfwInitJoysticksLinux") @export @feat(!WASM & FAST) => true;
fn void _glfwTerminateJoysticksLinux() @cname("_glfwTerminateJoysticksLinux") @export @feat(!WASM & FAST) {}
fn bool _glfwPlatformInitJoysticks() @cname("_glfwPlatformInitJoysticks") @export @feat(!WASM & FAST) => true;
fn void _glfwPlatformTerminateJoysticks() @cname("_glfwPlatformTerminateJoysticks") @export @feat(!WASM & FAST) {}
fn void _glfwDetectJoystickConnectionLinux() @cname("_glfwDetectJoystickConnectionLinux") @export @feat(!WASM & FAST) {}

enum MouseButton : int
{
	LEFT,
	RIGHT,
	MIDDLE
}

constdef Key : int
{
	NONE = 0,
	A = 65, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
	ZERO = 48, ONE, TWO, THREE, FOUR, FIVE, SIX, SEVEN, EIGHT, NINE,
	F1 = 290, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,
	ESCAPE = 256,
	ENTER = 257,
	TAB = 258,
	BACKSPACE = 259,
	INSERT = 260,
	DELETE = 261,
	RIGHT = 262,
	LEFT = 263,
	DOWN = 264,
	UP = 265,
	PAGE_UP = 266,
	PAGE_DOWN = 267,
	HOME = 268,
	END = 269,
	LEFT_SHIFT = 340,
	LEFT_CONTROL = 341,
	LEFT_ALT = 342,
	RIGHT_SHIFT = 344,
	RIGHT_CONTROL = 345,
	RIGHT_ALT = 346,
	SPACE = 32,
	MINUS = 45,
	EQUAL = 61,
	GRAVE = 96,
	SLASH = 47,
	BACKSLASH = 92,
	KP_ADD = 334,
	KP_SUBTRACT = 333,
	KP_ENTER = 335
}

fn RLColor to_rl_color(Color c) @inline => { c[0], c[1], c[2], c[3] };
fn RLRectangle to_rl_rect(Rect r) @inline => { r.x, r.y, r.width, r.height };
fn RLVector2 to_rl_vec2(Vec2 v) @inline => { v.x, v.y };

fn void init_window(int width, int height, String title)
{
	$if $feat(FAST):
		rl::set_trace_log_level(RLTraceLogLevel.NONE);
	$endif

	rl::set_config_flags(RLConfigFlag.WINDOW_RESIZABLE | RLConfigFlag.WINDOW_HIDDEN);
	rl::init_window(width, height, title.zstr_tcopy());
	rl::set_exit_key((RLKeyboardKey)0);

	$if !env::WASM:
		int monitor = rl::get_current_monitor();
		int screen_w = rl::get_monitor_width(monitor);
		int screen_h = rl::get_monitor_height(monitor);

		rl::set_window_size(screen_w, screen_h - 28);
		rl::set_window_position(0, 0);
		rl::set_target_fps(60);
		rl::maximize_window();
	$endif

	rl::clear_window_state(RLConfigFlag.WINDOW_HIDDEN);
}

fn void close_window() => rl::close_window();
fn bool should_close() => rl::window_should_close();
fn float get_frame_time() => rl::get_frame_time();
fn double get_time() => rl::get_time();
fn int get_screen_width() => rl::get_screen_width();
fn int get_screen_height() => rl::get_screen_height();

fn void begin_frame() => rl::begin_drawing();
fn void end_frame() => rl::end_drawing();
fn void clear_background(Color color) => rl::clear_background(to_rl_color(color));

fn void draw_rect(int x, int y, int w, int h, Color color)
{
	rl::draw_rectangle(x, y, w, h, to_rl_color(color));
}

fn void draw_rect_lines(int x, int y, int w, int h, Color color)
{
	rl::draw_rectangle_lines(x, y, w, h, to_rl_color(color));
}

fn void draw_line(int start_x, int start_y, int end_x, int end_y, Color color)
{
	rl::draw_line(start_x, start_y, end_x, end_y, to_rl_color(color));
}

fn void draw_triangle(Vec2 v1, Vec2 v2, Vec2 v3, Color color)
{
	rl::draw_triangle(to_rl_vec2(v1), to_rl_vec2(v2), to_rl_vec2(v3), to_rl_color(color));
}

fn void begin_scissor(int x, int y, int w, int h)
{
	rl::begin_scissor_mode(x, y, w, h);
}

fn void end_scissor()
{
	rl::end_scissor_mode();
}

fn Vec2 get_mouse_pos()
{
	RLVector2 p = rl::get_mouse_position();
	return { p.x, p.y };
}

fn float get_mouse_wheel() => rl::get_mouse_wheel_move();

fn bool is_mouse_down(MouseButton button)
{
	return rl::is_mouse_button_down((RLMouseButton)(int)button);
}

fn bool is_mouse_pressed(MouseButton button)
{
	return rl::is_mouse_button_pressed((RLMouseButton)(int)button);
}

fn bool is_mouse_released(MouseButton button)
{
	return rl::is_mouse_button_released((RLMouseButton)(int)button);
}

fn bool is_key_pressed(Key key) => rl::is_key_pressed((RLKeyboardKey)key);
fn bool is_key_down(Key key) => rl::is_key_down((RLKeyboardKey)key);
fn bool is_key_repeat(Key key) => rl::is_key_pressed_repeat((RLKeyboardKey)key);
fn int get_char_pressed() => rl::get_char_pressed();

fn String? get_clipboard(Allocator allocator) => @pool()
{
	ZString clip = rl::get_clipboard_text();
	if (clip == null) return NOT_FOUND~;
	String s = clip.str_view();
	if (s.len == 0) return NOT_FOUND~;
	return s.copy(allocator);
}

fn void set_clipboard(String text) => @pool()
{
	if (text.len > 15 * 1024 * 1024) return;
	rl::set_clipboard_text(text.zstr_tcopy());
}