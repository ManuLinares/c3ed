module c3ed;
import std;

fn String resolve_path_string(String raw_path, Allocator allocator = tmem)
{
	if (raw_path == "~")
	{
		if (try Path home = path::home_directory(allocator)) return ((String)home).copy(allocator);
	}
	else if (raw_path.starts_with("~/") || raw_path.starts_with("~\\"))
	{
		if (try Path home = path::home_directory(allocator))
		{
			if (raw_path.len <= 2) return ((String)home).copy(allocator);
			Path appended = home.append(allocator, raw_path[2..]) ?? home;
			return ((String)appended).copy(allocator);
		}
	}
	return raw_path;
}

enum DiagnosticSeverity : char
{
	ERROR,
	WARNING,
	NOTE
}

struct Diagnostic
{
	String filepath;
	int line;
	int col;
	String message;
	DiagnosticSeverity severity;
}

fn void Diagnostic.free(&self, Allocator allocator = mem)
{
	if (self.filepath.len > 0) alloc::free(allocator, self.filepath.ptr);
	if (self.message.len > 0) alloc::free(allocator, self.message.ptr);
	*self = { };
}

struct DiagnosticStore
{
	List{Diagnostic} items;
}

fn void DiagnosticStore.init(&self, Allocator allocator = mem)
{
	self.items.init(allocator, 32);
}

fn void DiagnosticStore.clear(&self)
{
	foreach (&diag : self.items)
	{
		diag.free(mem);
	}
	self.items.clear();
}

fn void DiagnosticStore.parse_output(&self, String output) => @pool()
{
	self.clear();
	if (output.len == 0) return;

	Splitter lines = output.tokenize("\n");
	while (try l = lines.next())
	{
		sz colon1 = l.index_of_char(':') ?? 0;
		if (colon1 == 0) continue;

		String path = l[:colon1].trim();
		String rest1 = l[colon1 + 1..];

		sz colon2 = rest1.index_of_char(':') ?? 0;
		if (colon2 == 0) continue;

		int line_num = rest1[:colon2].to_int() ?? 0;
		if (line_num <= 0) continue;

		String rest2 = rest1[colon2 + 1..];
		sz colon3 = rest2.index_of_char(':') ?? 0;
		int col_num = 1;
		String msg = rest2;

		if (colon3 > 0)
		{
			col_num = rest2[:colon3].to_int() ?? 1;
			msg = rest2[colon3 + 1..].trim();
		}

		DiagnosticSeverity sev = ERROR;
		if (msg.contains("Warning") || msg.contains("warning"))
		{
			sev = WARNING;
		}
		else if (msg.contains("Note") || msg.contains("note"))
		{
			sev = NOTE;
		}

		self.items.push({
			.filepath = path.copy(mem),
			.line     = line_num,
			.col      = col_num,
			.message  = msg.copy(mem),
			.severity = sev
		});
	}
}

fn Diagnostic*? DiagnosticStore.get_at(&self, String filepath, int line)
{
	if (filepath.len == 0 || self.items.len() == 0) return NOT_FOUND~;
	foreach (&d : self.items)
	{
		if (d.line == line && (d.filepath.ends_with(filepath) || filepath.ends_with(d.filepath)))
		{
			return d;
		}
	}
	return NOT_FOUND~;
}

enum GitLineStatus : char
{
	NONE,
	ADDED,
	MODIFIED,
	DELETED
}

struct GitHunk
{
	int line_start;
	int line_count;
	GitLineStatus status;
}

struct GitDiffStore
{
	String filepath;
	List{GitHunk} hunks;
}

fn void GitDiffStore.init(&self, Allocator allocator = mem)
{
	self.filepath = "";
	self.hunks.init(allocator, 16);
}

fn void GitDiffStore.free(&self, Allocator allocator = mem)
{
	if (self.filepath.len > 0) alloc::free(allocator, self.filepath.ptr);
	self.hunks.free();
	*self = { };
}

fn GitLineStatus GitDiffStore.get_status(&self, int line_idx)
{
	foreach (&h : self.hunks)
	{
		if (line_idx >= h.line_start && line_idx < h.line_start + h.line_count)
		{
			return h.status;
		}
	}
	return NONE;
}

fn void GitDiffStore.update(&self, String filepath, int total_lines) => @pool()
{
	$if env::WIN32:
		return;
	$else
		if (!config::settings.show_git_gutter) return;

		if (filepath.len == 0 || !file::exists(filepath) || is_binary_extension(filepath)) return;

		if (self.filepath != filepath)
		{
			if (self.filepath.len > 0) mem::free(self.filepath.ptr);
			self.filepath = filepath.copy(mem);
		}

		self.hunks.clear();

		String[*] cmd = {
			"git",
			"-c", "core.pager=",
			"--no-pager",
			"diff",
			"--no-color",
			"-U0",
			"--",
			filepath
		};

		char[16384] out_buf;
		SpawnOptions opts = STDERR_TO_STDOUT | INHERIT_ENV;
		String? diff_out = process::run_capture_stdout(&out_buf, cmd[..], options: opts);
		if (catch diff_out) return;
		if (diff_out.len == 0 || diff_out.starts_with("fatal:") || diff_out.starts_with("error:")) return;

		Splitter lines = diff_out.tokenize("\n");
		while (try l = lines.next())
		{
			if (!l.starts_with("@@")) continue;

			sz minus_idx = l.index_of_char('-') ?? 0;
			sz plus_idx  = l.index_of_char('+') ?? 0;
			if (minus_idx == 0 || plus_idx == 0 || plus_idx <= minus_idx) continue;

			String old_hunk = l[minus_idx + 1..plus_idx - 1].trim();
			String new_hunk = l[plus_idx + 1..];
			sz space_idx = new_hunk.index_of_char(' ') ?? new_hunk.len;
			new_hunk = new_hunk[:space_idx].trim();

			int old_start = 1;
			int old_count = 1;
			if (try comma = old_hunk.index_of_char(','))
			{
				old_start = old_hunk[:comma].to_int() ?? 1;
				old_count = old_hunk[comma + 1..].to_int() ?? 1;
			}
			else
			{
				old_start = old_hunk.to_int() ?? 1;
				old_count = 1;
			}

			int new_start = 1;
			int new_count = 1;
			if (try comma = new_hunk.index_of_char(','))
			{
				new_start = new_hunk[:comma].to_int() ?? 1;
				new_count = new_hunk[comma + 1..].to_int() ?? 1;
			}
			else
			{
				new_start = new_hunk.to_int() ?? 1;
				new_count = 1;
			}

			if (new_count == 0)
			{
				self.hunks.push({ math::max(0, new_start - 1), 1, DELETED });
			}
			else
			{
				GitLineStatus status = (old_count > 0) ? MODIFIED : ADDED;
				self.hunks.push({ math::max(0, new_start - 1), new_count, status });
			}
		}
	$endif
}

enum SymbolKind : char
{
	FUNCTION,
	STRUCT,
	UNION,
	ENUM,
	BITSTRUCT,
	MACRO,
	TYPE_ALIAS,
	CONSTANT,
	FAULT,
	VARIABLE,
	FIELD,
	MODULE
}

struct SymbolItem
{
	String name;
	SymbolKind kind;
	String signature;
	String doc_comment;
	String filepath;
	String parent_type;
	int line;
	int col;
}

fn void SymbolItem.free(&self, Allocator allocator = mem)
{
	if (self.name.len > 0) alloc::free(allocator, self.name.ptr);
	if (self.signature.len > 0) alloc::free(allocator, self.signature.ptr);
	if (self.doc_comment.len > 0) alloc::free(allocator, self.doc_comment.ptr);
	if (self.filepath.len > 0) alloc::free(allocator, self.filepath.ptr);
	if (self.parent_type.len > 0) alloc::free(allocator, self.parent_type.ptr);
	*self = { };
}

struct DeclKeyword
{
	String kw;
	SymbolKind kind;
	char[] stop_chars;
	bool is_callable;
}

const DeclKeyword[*] DECL_KEYWORDS = {
	{ "fn ",        FUNCTION,   "(",                     true  },
	{ "macro ",     MACRO,      "(",                     true  },
	{ "struct ",    STRUCT,     {' ', '{', '<', '('},    false },
	{ "union ",     UNION,      {' ', '{', '<', '('},    false },
	{ "enum ",      ENUM,       {' ', '{', ':', '('},    false },
	{ "bitstruct ", BITSTRUCT,  {' ', '{', ':'},         false },
	{ "const ",     CONSTANT,   {'=', ';'},              false },
	{ "faultdef ",  FAULT,      {';', ' '},              false },
	{ "alias ",     TYPE_ALIAS, {'=', ';', '<', '@', ' '}, false },
	{ "typedef ",   TYPE_ALIAS, {'=', ';', '<', '@', ' '}, false },
};

struct SymbolIndex
{
	List{SymbolItem} symbols;
	bool initialized;
}

fn void SymbolIndex.init(&self, Allocator allocator = mem)
{
	self.symbols.init(allocator, 2048);
	self.initialized = false;
}

fn void SymbolIndex.free(&self, Allocator allocator = mem)
{
	foreach (&s : self.symbols) s.free(allocator);
	self.symbols.free();
	*self = { };
}

fn void SymbolIndex.index_source_text(&self, String filepath, String text, Allocator allocator = mem) => @pool()
{
	if (text.len == 0) return;

	Splitter lines = text.tokenize_all("\n");
	int line_num = 1;
	DString active_doc;
	active_doc.tinit();
	bool inside_doc = false;
	bool inside_block_comment = false;

	String active_container = "";
	String current_module = "";
	int container_brace_depth = 0;

	while (try line_raw = lines.next())
	{
		String l = line_raw.trim();
		if (l.len == 0 || l.starts_with("//") || l.starts_with("#!"))
		{
			line_num++;
			continue;
		}

		if (l.starts_with("module "))
		{
			String mod_rest = l["module ".len..].trim(" ;");
			if (try semi = mod_rest.index_of_char(';')) mod_rest = mod_rest[:semi].trim();
			sz last_col = mod_rest.rindex_of("::") ?? -1;
			current_module = (last_col >= 0 ? mod_rest[last_col + 2..] : mod_rest);
			line_num++;
			continue;
		}

		if (!inside_block_comment && l.starts_with("<*"))
		{
			if (l.ends_with("*>") && l.len >= 4)
			{
				active_doc.clear();
				active_doc.append(l[2..l.len - 2].trim());
				line_num++;
				continue;
			}
			inside_doc = true;
			active_doc.clear();
			active_doc.append(l[2..].trim());
			line_num++;
			continue;
		}

		if (inside_doc)
		{
			if (l.ends_with("*>"))
			{
				inside_doc = false;
				active_doc.append_char(' ');
				active_doc.append(l[:l.len - 2].trim());
			}
			else
			{
				active_doc.append_char(' ');
				active_doc.append(l);
			}
			line_num++;
			continue;
		}

		if (!inside_doc && !inside_block_comment && l.starts_with("/*"))
		{
			if (l.ends_with("*/") && l.len >= 4)
			{
				line_num++;
				continue;
			}
			inside_block_comment = true;
			line_num++;
			continue;
		}

		if (inside_block_comment)
		{
			if (l.ends_with("*/") || l.contains("*/"))
			{
				inside_block_comment = false;
			}
			line_num++;
			continue;
		}

		if (active_container.len > 0)
		{
			if (l.contains_char('{')) container_brace_depth++;
			if (l.contains_char('}'))
			{
				container_brace_depth--;
				if (container_brace_depth <= 0)
				{
					active_container = "";
					container_brace_depth = 0;
				}
			}
			else if (container_brace_depth > 0)
			{
				if (l.ends_with(";") && !l.starts_with("fn ") && !l.starts_with("struct ") && !l.starts_with("union "))
				{
					String field_line = l[:l.len - 1].trim();
					sz sp_idx = field_line.rindex_of_char(' ') ?? -1;
					if (sp_idx >= 0)
					{
						String fname = field_line[sp_idx + 1..].trim();
						if (fname.len > 0 && (fname[0].is_alpha() || fname[0] == '_'))
						{
							SymbolItem fsym = {
								.name        = fname.copy(allocator),
								.kind        = FIELD,
								.signature   = l.copy(allocator),
								.filepath    = filepath.copy(allocator),
								.parent_type = active_container.copy(allocator),
								.line        = line_num,
								.col         = (int)(line_raw.index_of(fname) ?? 0) + 1
							};
							self.symbols.push(fsym);
						}
					}
				}
				else if (l.ends_with(",") || !l.contains_char(';'))
				{
					String entry_name = l.trim(" ,{}=0123456789;");
					if (entry_name.len > 0 && entry_name[0].is_upper())
					{
						sz sp_i = entry_name.index_of_char(' ') ?? entry_name.len;
						entry_name = entry_name[:sp_i];
						SymbolItem esym = {
							.name        = entry_name.copy(allocator),
							.kind        = CONSTANT,
							.signature   = l.copy(allocator),
							.filepath    = filepath.copy(allocator),
							.parent_type = active_container.copy(allocator),
							.line        = line_num,
							.col         = (int)(line_raw.index_of(entry_name) ?? 0) + 1
						};
						self.symbols.push(esym);
					}
				}
			}
		}

		SymbolItem sym = { };
		bool found = false;

		foreach (&dk : DECL_KEYWORDS)
		{
			if (l.starts_with(dk.kw))
			{
				String rest = l[dk.kw.len..].trim();
				sz end_idx = dk.is_callable
					? (rest.index_of_char('(') ?? 0)
					: (rest.index_of_chars(dk.stop_chars) ?? rest.len);

				if (end_idx > 0)
				{
					found = true;
					sym.kind = dk.kind;
					String pre = rest[:end_idx].trim();
					sz sp = pre.rindex_of_char(' ') ?? -1;
					String full_name = (sp >= 0 ? pre[sp + 1..] : pre).trim();

					if (try dot_pos = full_name.index_of_char('.'))
					{
						sym.parent_type = full_name[:dot_pos].copy(allocator);
						sym.name = full_name[dot_pos + 1..].copy(allocator);
					}
					else
					{
						sym.name = full_name.copy(allocator);
						if (current_module.len > 0) sym.parent_type = current_module.copy(allocator);
					}
					sym.signature = l.copy(allocator);

					if (dk.kind == STRUCT || dk.kind == UNION || dk.kind == BITSTRUCT || dk.kind == ENUM)
					{
						active_container = sym.name;
						container_brace_depth = l.contains_char('{') ? 1 : 0;
					}
				}
				break;
			}
		}

		if (found && sym.name.len > 0)
		{
			sym.filepath = filepath.copy(allocator);
			sym.line = line_num;
			sym.col = (int)(line_raw.index_of(sym.name) ?? 0) + 1;
			sym.doc_comment = active_doc.str_view().trim().copy(allocator);
			active_doc.clear();
			self.symbols.push(sym);
		}
		line_num++;
	}
}

fn SymbolItem*? SymbolIndex.find_symbol_closest(&self, String name, int near_line = 0)
{
	if (name.len == 0 || self.symbols.len() == 0) return NOT_FOUND~;

	SymbolItem* best = null;
	int best_dist = int::max;

	foreach (&sym : self.symbols)
	{
		bool matches = (sym.name == name);
		if (!matches && sym.name.ends_with(name))
		{
			if (sym.name.len > name.len && sym.name[sym.name.len - name.len - 1] == '.')
			{
				matches = true;
			}
		}

		if (matches)
		{
			if (near_line > 0)
			{
				if (sym.line <= near_line)
				{
					int dist = near_line - sym.line;
					if (dist < best_dist)
					{
						best_dist = dist;
						best = sym;
					}
				}
				else if (best == null)
				{
					best = sym;
				}
			}
			else
			{
				return sym;
			}
		}
	}
	if (best != null) return best;
	return NOT_FOUND~;
}

struct FileWatcher
{
	float check_interval;
	float timer;
}

fn void FileWatcher.init(&self, float check_interval = config::TIMING.file_watcher_interval)
{
	self.check_interval = check_interval;
	self.timer = 0.0f;
}

fn bool FileWatcher.should_poll(&self, float dt)
{
	self.timer += dt;
	if (self.timer < self.check_interval) return false;
	self.timer = 0.0f;
	return true;
}

struct Workspace
{
	String root_dir;
	List{String} files;
	bool files_valid;

	SymbolIndex lsp;
	DiagnosticStore diagnostics;
	GitDiffStore git;
	FileWatcher watcher;
}

fn void Workspace.init(&self, Allocator allocator = mem, String root_dir = ".")
{
	self.root_dir = root_dir.copy(allocator);
	self.files.init(allocator, 512);
	self.files_valid = false;
	self.lsp.init(allocator);
	self.diagnostics.init(allocator);
	self.git.init(allocator);
	self.watcher.init(config::TIMING.file_watcher_interval);

	self.index_workspace_symbols();
}

fn void Workspace.free(&self, Allocator allocator = mem)
{
	if (self.root_dir.len > 0) alloc::free(allocator, self.root_dir.ptr);
	self.invalidate_files();
	self.files.free();
	self.lsp.free(allocator);
	self.diagnostics.clear();
	self.diagnostics.items.free();
	self.git.free(allocator);
	*self = { };
}

fn void Workspace.invalidate_files(&self)
{
	foreach (s : self.files)
	{
		if (s.len > 0) mem::free(s.ptr);
	}
	self.files.clear();
	self.files_valid = false;
}

fn void Workspace.refresh_files(&self) => @pool()
{
	self.invalidate_files();
	collect_workspace_files(mem, (Path)self.root_dir, &self.files, c3_only: false, max_files: 5000);
	self.files_valid = true;
}

fn void Workspace.ensure_files(&self)
{
	if (!self.files_valid || self.files.len() == 0)
	{
		self.refresh_files();
	}
}

fn void Workspace.index_workspace_symbols(&self) => @pool()
{
	List{String} c3_files;
	c3_files.tinit(512);
	collect_workspace_files(tmem, (Path)self.root_dir, &c3_files, c3_only: true, max_files: 1000);

	foreach (filepath : c3_files)
	{
		@pool()
		{
			if (file::get_size(filepath) ?? 0 > 2 * 1024 * 1024) return;
			char[]? code_opt = file::load(tmem, filepath);
			if (try code = code_opt)
			{
				self.lsp.index_source_text(filepath, (String)code, mem);
			}
		};
	}
	self.lsp.initialized = true;
}

fn void Workspace.poll_disk_changes(
	&self,
	List{Tab}* tabs,
	int* pending_reload_tab,
	ModalKind* active_modal,
	float dt
) => @pool()
{
	if (!self.watcher.should_poll(dt)) return;

	for (sz idx = 0; idx < tabs.len(); idx++)
	{
		Tab* tab = &(*tabs)[idx];
		if (!tab.doc.is_file_specified || tab.doc.filepath.len == 0) continue;
		Time? mtime = file::last_modified(tab.doc.filepath);
		if (catch mtime) continue;

		Time cur_mtime = mtime;
		if (tab.doc.last_disk_mtime != (Time)0 && cur_mtime > tab.doc.last_disk_mtime)
		{
			tab.doc.last_disk_mtime = cur_mtime;
			self.invalidate_files();

			if (!tab.doc.is_modified)
			{
				char[]? new_content = file::load(tmem, tab.doc.filepath);
				if (try c = new_content)
				{
					tab.doc.table.free();
					tab.doc.table.init(mem, (char[])((String)c).copy(mem));
					tab.doc.rebuild_line_index();
					tab.doc.is_modified = false;
					self.git.update(tab.doc.filepath, tab.doc.get_total_lines());
				}
			}
			else
			{
				*pending_reload_tab = (int)idx;
				*active_modal = CONFIRM_DISK_RELOAD;
			}
		}
		else if (tab.doc.last_disk_mtime == (Time)0)
		{
			tab.doc.last_disk_mtime = cur_mtime;
		}
	}
}

const String[*] IGNORED_DIRECTORIES = {
	".git", ".venv", "venv", "env", "node_modules",
	".cache", ".local", ".config", ".vscode", ".idea", ".vs", "build",
	"bin", "obj", "target", "dist", "out", "pkg", "dependencies",
	".pytest_cache", "__pycache__", ".mypy_cache",
	".svn", ".hg", ".dart_tool", ".gradle", "snap", "flatpak"
};

fn bool is_ignored_dirname(String name)
{
	if (name.len == 0) return false;
	if (name.starts_with(".") && name != ".") return true;
	if (name.starts_with("build_") || name.starts_with("build-") || name.starts_with(".build")) return true;
	foreach (ignored : IGNORED_DIRECTORIES)
	{
		if (name == ignored) return true;
	}
	return false;
}

fn bool is_binary_extension(String filepath)
{
	String ext = filepath.file_tbasename() ?? filepath;
	return ext.ends_with(".png")  || ext.ends_with(".jpg")  || ext.ends_with(".jpeg") ||
	       ext.ends_with(".gif")  || ext.ends_with(".ico")  || ext.ends_with(".bmp")  ||
	       ext.ends_with(".exe")  || ext.ends_with(".dll")  || ext.ends_with(".so")   ||
	       ext.ends_with(".dylib")|| ext.ends_with(".o")    || ext.ends_with(".a")    ||
	       ext.ends_with(".lib")  || ext.ends_with(".bin")  || ext.ends_with(".dat")  ||
	       ext.ends_with(".wasm") || ext.ends_with(".zip")  || ext.ends_with(".tar")  ||
	       ext.ends_with(".gz")   || ext.ends_with(".7z")   || ext.ends_with(".pdf")  ||
	       ext.ends_with(".ttf")  || ext.ends_with(".otf")  || ext.ends_with(".woff") ||
	       ext.ends_with(".woff2")|| ext.ends_with(".mp3")  || ext.ends_with(".wav")  ||
	       ext.ends_with(".mp4")  || ext.ends_with(".mkv")  || ext.ends_with(".class")||
	       ext.ends_with(".pdb")  || ext.ends_with(".zst")  || ext.ends_with(".data");
}

fn void collect_workspace_files(
	Allocator allocator,
	Path dir,
	List{String}* out_files,
	bool c3_only = false,
	int depth = 0,
	sz max_files = 5000
) => @pool()
{
	if (depth > 8 || out_files.len() >= max_files) return;

	PathList? entries_opt = path::ls(tmem, dir, no_dirs: false, no_symlinks: true, relative: true, rebase: dir);
	if (catch entries_opt) return;
	PathList entries = entries_opt;

	List{Path} sub_dirs;
	sub_dirs.tinit(32);

	foreach (entry_path : entries)
	{
		if (out_files.len() >= max_files) break;

		String p_str = (String)entry_path;
		String base_name = p_str.file_tbasename() ?? p_str;
		if (base_name.len == 0 || base_name == "." || base_name == "..") continue;
		if (is_ignored_dirname(base_name)) continue;

		if (path::is_dir(entry_path))
		{
			sub_dirs.push(entry_path);
		}
		else if (path::is_file(entry_path))
		{
			if (is_binary_extension(p_str)) continue;
			if (c3_only && !p_str.ends_with(".c3")) continue;

			out_files.push(p_str.copy(allocator));
		}
	}

	foreach (sub_dir : sub_dirs)
	{
		if (out_files.len() >= max_files) break;
		collect_workspace_files(allocator, sub_dir, out_files, c3_only, depth + 1, max_files);
	}
}
