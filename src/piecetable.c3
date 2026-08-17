module c3ed;
import std, libc;

enum BufferSource : char
{
	ORIGINAL,
	ADD
}

struct Piece
{
	BufferSource source;
	BytePos offset;
	BytePos length;
	sz line_count;
}

struct PieceMutation
{
	sz piece_index;
	List{Piece} old_pieces;
	List{Piece} new_pieces;
}

struct UndoTransaction
{
	List{PieceMutation} mutations;
	List{Cursor} cursors_before;
	List{Cursor} cursors_after;
}

struct PieceSpan
{
	sz start_idx;
	BytePos start_offset;
	sz end_idx;
	BytePos end_offset;
}

struct PieceTable (Printable)
{
	char[] original_buffer;
	FileMmap mmap_handle;
	bool is_mmap;
	bool owns_buffer;

	char* add_buffer;
	BytePos add_capacity;
	BytePos add_len;

	List{Piece} pieces;
	Allocator allocator;

	List{UndoTransaction*} undo_stack;
	List{UndoTransaction*} redo_stack;
	UndoTransaction* active_transaction;
	bool in_transaction;

	BytePos cached_total_length;
}

const BytePos DEFAULT_ADD_CAPACITY = 4096;

fn void PieceTable.init(
	&self,
	Allocator allocator = mem,
	char[] initial_text = { },
	bool is_mmap = false,
	FileMmap mmap_handle = { },
	bool owns_buffer = true
)
{
	self.allocator = allocator;
	self.original_buffer = initial_text;
	self.is_mmap = is_mmap;
	self.mmap_handle = mmap_handle;
	self.owns_buffer = owns_buffer;

	self.add_capacity = DEFAULT_ADD_CAPACITY;
	self.add_len = 0;
	self.add_buffer = alloc::alloc_array(allocator, char, self.add_capacity);

	self.pieces.init(allocator, 16);
	self.undo_stack.init(allocator, 32);
	self.redo_stack.init(allocator, 32);
	self.active_transaction = null;
	self.in_transaction = false;

	if (initial_text.len > 0)
	{
		sz lines = count_newlines(initial_text);
		self.pieces.push({ .source = ORIGINAL, .offset = 0, .length = initial_text.len, .line_count = lines });
		self.cached_total_length = initial_text.len;
	}
	else
	{
		self.cached_total_length = 0;
	}
}

fn void PieceTable.free(&self)
{
	if (self.add_buffer)
	{
		alloc::free(self.allocator, self.add_buffer);
		self.add_buffer = null;
	}
	self.pieces.free();
	self.clear_undo_redo();
	self.undo_stack.free();
	self.redo_stack.free();

	if (self.is_mmap)
	{
		(void)self.mmap_handle.destroy();
	}
	else if (self.owns_buffer && self.original_buffer.len > 0)
	{
		alloc::free(self.allocator, self.original_buffer.ptr);
	}
	*self = { };
}

fn void free_undo_transaction(Allocator allocator, UndoTransaction* tx) @private
{
	if (!tx) return;
	for (sz i = 0; i < tx.mutations.len(); i++)
	{
		tx.mutations[i].old_pieces.free();
		tx.mutations[i].new_pieces.free();
	}
	tx.mutations.free();
	tx.cursors_before.free();
	tx.cursors_after.free();
	alloc::free(allocator, tx);
}

fn void PieceTable.clear_undo_redo(&self)
{
	while (try act = self.undo_stack.pop())
	{
		free_undo_transaction(self.allocator, act);
	}
	while (try act = self.redo_stack.pop())
	{
		free_undo_transaction(self.allocator, act);
	}
	if (self.active_transaction)
	{
		free_undo_transaction(self.allocator, self.active_transaction);
		self.active_transaction = null;
		self.in_transaction = false;
	}
}

fn void PieceTable.begin_transaction(&self, List{Cursor}* cursors_before)
{
	if (self.in_transaction) return;
	while (try act = self.redo_stack.pop())
	{
		free_undo_transaction(self.allocator, act);
	}

	UndoTransaction* tx = alloc::new(self.allocator, UndoTransaction);
	tx.mutations.init(self.allocator, 8);
	tx.cursors_before.init(self.allocator, cursors_before.len());
	tx.cursors_after.init(self.allocator, cursors_before.len());

	for (sz i = 0; i < cursors_before.len(); i++)
	{
		tx.cursors_before.push((*cursors_before)[i]);
	}

	self.active_transaction = tx;
	self.in_transaction = true;
}

fn void PieceTable.end_transaction(&self, List{Cursor}* cursors_after)
{
	if (!self.in_transaction || !self.active_transaction) return;

	UndoTransaction* tx = self.active_transaction;
	self.active_transaction = null;
	self.in_transaction = false;

	if (tx.mutations.len() == 0)
	{
		free_undo_transaction(self.allocator, tx);
		return;
	}

	for (sz i = 0; i < cursors_after.len(); i++)
	{
		tx.cursors_after.push((*cursors_after)[i]);
	}

	self.undo_stack.push(tx);
}

fn void PieceTable.record_mutation(&self, PieceMutation mutation)
{
	if (self.in_transaction && self.active_transaction)
	{
		self.active_transaction.mutations.push(mutation);
	}
	else
	{
		while (try act = self.redo_stack.pop())
		{
			free_undo_transaction(self.allocator, act);
		}
		UndoTransaction* tx = alloc::new(self.allocator, UndoTransaction);
		tx.mutations.init(self.allocator, 1);
		tx.cursors_before.init(self.allocator, 0);
		tx.cursors_after.init(self.allocator, 0);
		tx.mutations.push(mutation);
		self.undo_stack.push(tx);
	}
}

fn BytePos PieceTable.len(&self) @operator(len) @inline => self.cached_total_length;

fn char PieceTable.get(&self, BytePos index) @operator([])
{
	assert(index < self.cached_total_length, "PieceTable index out of bounds");
	BytePos current_offset = 0;

	foreach (&p : self.pieces)
	{
		if (index < current_offset + p.length)
		{
			BytePos local_idx = index - current_offset;
			return (p.source == ORIGINAL)
				? self.original_buffer[p.offset + local_idx]
				: self.add_buffer[p.offset + local_idx];
		}
		current_offset += p.length;
	}
	unreachable("Unreachable piece table index search");
}

fn char PieceTable.char_at(&self, BytePos index, char fallback = '\0') @inline
{
	if (index >= self.cached_total_length) return fallback;
	return self.get(index);
}

fn char[] PieceTable.piece_slice(&self, Piece* p) @inline
{
	return (p.source == ORIGINAL)
		? self.original_buffer[p.offset:p.length]
		: self.add_buffer[p.offset:p.length];
}

fn bool PieceTable.match_cross_boundary(&self, BytePos global_pos, String needle, bool case_sensitive)
{
	sz nlen = needle.len;
	if (global_pos + nlen > self.cached_total_length) return false;

	for (sz j = 0; j < nlen; j++)
	{
		char doc_c = self.char_at(global_pos + (BytePos)j);
		char ned_c = needle[j];
		if (case_sensitive)
		{
			if (doc_c != ned_c) return false;
		}
		else
		{
			if (doc_c != ned_c && ascii::to_lower(doc_c) != ascii::to_lower(ned_c)) return false;
		}
	}
	return true;
}

fn BytePos? PieceTable.find_forward(&self, BytePos start_pos, String needle, bool case_sensitive)
{
	sz nlen = needle.len;
	if (nlen == 0 || self.cached_total_length < nlen || start_pos + nlen > self.cached_total_length)
	{
		return NOT_FOUND~;
	}

	char n0 = needle[0];
	char lower_n0 = ascii::to_lower(n0);
	char upper_n0 = ascii::to_upper(n0);

	BytePos current_piece_start = 0;

	for (sz pi = 0; pi < self.pieces.len(); pi++)
	{
		Piece* p = &self.pieces[pi];
		BytePos p_len = p.length;
		BytePos next_piece_start = current_piece_start + p_len;

		if (start_pos >= next_piece_start)
		{
			current_piece_start = next_piece_start;
			continue;
		}

		sz local_start = (start_pos > current_piece_start) ? (sz)(start_pos - current_piece_start) : 0;
		char[] slice = self.piece_slice(p);
		char* ptr = slice.ptr;

		if (case_sensitive)
		{
			sz cur_idx = local_start;
			while (cur_idx < slice.len)
			{
				void* found = libc::memchr((void*)&ptr[cur_idx], (CInt)n0, (usz)(slice.len - cur_idx));
				if (found == null) break;

				sz match_local = (sz)((uptr)found - (uptr)ptr);
				BytePos global_match = current_piece_start + (BytePos)match_local;

				if (match_local + nlen <= slice.len)
				{
					if (nlen == 1 || libc::memcmp((void*)&ptr[match_local + 1], (void*)&needle[1], (usz)(nlen - 1)) == 0)
					{
						return global_match;
					}
				}
				else
				{
					if (self.match_cross_boundary(global_match, needle, true))
					{
						return global_match;
					}
				}
				cur_idx = match_local + 1;
			}
		}
		else
		{
			sz cur_idx = local_start;
			sz max_local = slice.len >= nlen ? slice.len - nlen : 0;

			while (cur_idx <= max_local)
			{
				char c = ptr[cur_idx];
				if (c == lower_n0 || c == upper_n0)
				{
					bool matched = true;
					for (sz j = 1; j < nlen; j++)
					{
						char dc = ptr[cur_idx + j];
						char nc = needle[j];
						if (dc != nc && ascii::to_lower(dc) != ascii::to_lower(nc))
						{
							matched = false;
							break;
						}
					}
					if (matched)
					{
						return current_piece_start + (BytePos)cur_idx;
					}
				}
				cur_idx++;
			}

			while (cur_idx < slice.len)
			{
				char c = ptr[cur_idx];
				if (c == lower_n0 || c == upper_n0)
				{
					BytePos global_match = current_piece_start + (BytePos)cur_idx;
					if (self.match_cross_boundary(global_match, needle, false))
					{
						return global_match;
					}
				}
				cur_idx++;
			}
		}

		current_piece_start = next_piece_start;
	}

	return NOT_FOUND~;
}

fn BytePos? PieceTable.find_backward(&self, BytePos max_start, String needle, bool case_sensitive)
{
	sz nlen = needle.len;
	if (nlen == 0 || self.cached_total_length < nlen)
	{
		return NOT_FOUND~;
	}

	BytePos max_valid = self.cached_total_length - nlen;
	BytePos start = math::min(max_start, max_valid);

	char n0 = needle[0];
	char lower_n0 = ascii::to_lower(n0);
	char upper_n0 = ascii::to_upper(n0);

	for (BytePos pos = start + 1; pos > 0; pos--)
	{
		BytePos cur = pos - 1;
		char c = self.char_at(cur);
		bool first_matches = case_sensitive ? (c == n0) : (c == lower_n0 || c == upper_n0);
		if (first_matches)
		{
			if (self.match_cross_boundary(cur, needle, case_sensitive))
			{
				return cur;
			}
		}
	}
	return NOT_FOUND~;
}

fn int PieceTable.count_matches(&self, String needle, bool case_sensitive, int max_count = int::max)
{
	sz nlen = needle.len;
	if (nlen == 0 || self.cached_total_length < nlen) return 0;

	int count = 0;
	BytePos pos = 0;
	while (pos + nlen <= self.cached_total_length)
	{
		if (try match_pos = self.find_forward(pos, needle, case_sensitive))
		{
			count++;
			if (count >= max_count) break;
			pos = match_pos + nlen;
		}
		else
		{
			break;
		}
	}
	return count;
}

fn void PieceTable.ensure_add_capacity(&self, BytePos needed)
{
	if (self.add_len + needed <= self.add_capacity) return;
	BytePos new_cap = math::max(self.add_capacity * 2, self.add_len + needed + 1024);
	self.add_buffer = alloc::realloc(self.allocator, self.add_buffer, new_cap);
	self.add_capacity = new_cap;
}

fn sz count_newlines(char[] text) @private
{
	sz count = 0;
	foreach (c : text)
	{
		if (c == '\n') count++;
	}
	return count;
}

fn Piece make_sub_piece(PieceTable* pt, Piece p, BytePos local_start, BytePos local_len) @private
{
	char[] piece_bytes = (p.source == ORIGINAL)
		? pt.original_buffer[p.offset + local_start:local_len]
		: pt.add_buffer[p.offset + local_start:local_len];

	sz lines = count_newlines(piece_bytes);
	return { .source = p.source, .offset = p.offset + local_start, .length = local_len, .line_count = lines };
}

fn void PieceTable.recalculate_total_length(&self)
{
	BytePos total = 0;
	foreach (&p : self.pieces) total += p.length;
	self.cached_total_length = total;
}

fn bool PieceTable.find_piece_span(&self, BytePos s, BytePos e, PieceSpan* out_span)
{
	BytePos current_offset = 0;
	bool found_start = false;
	bool found_end = false;

	for (sz i = 0; i < self.pieces.len(); i++)
	{
		Piece p = self.pieces[i];
		BytePos next_offset = current_offset + p.length;

		if (!found_start && s >= current_offset
			&& (s < next_offset || (s == next_offset && i + 1 == self.pieces.len())))
		{
			out_span.start_idx = i;
			out_span.start_offset = s - current_offset;
			found_start = true;
		}

		if (!found_end && e > current_offset && e <= next_offset)
		{
			out_span.end_idx = i;
			out_span.end_offset = e - current_offset;
			found_end = true;
			break;
		}
		current_offset = next_offset;
	}

	return found_start && found_end;
}

fn void PieceTable.insert_bytes(&self, BytePos pos, char[] bytes)
{
	if (bytes.len == 0) return;
	BytePos byte_len = bytes.len;

	self.ensure_add_capacity(byte_len);
	BytePos add_offset = self.add_len;
	mem::copy(&self.add_buffer[add_offset], bytes.ptr, byte_len);
	self.add_len += byte_len;

	sz lines = count_newlines(bytes);
	Piece new_p = { .source = ADD, .offset = add_offset, .length = byte_len, .line_count = lines };

	PieceMutation mut;
	switch
	{
		case pos == 0:
			mut.piece_index = 0;
			mut.old_pieces.init(self.allocator, 0);
			mut.new_pieces.init(self.allocator, 1);
			mut.new_pieces.push(new_p);
			self.pieces.insert_at(0, new_p);

		case pos >= self.cached_total_length:
			sz idx = self.pieces.len();
			mut.piece_index = idx;
			mut.old_pieces.init(self.allocator, 0);
			mut.new_pieces.init(self.allocator, 1);
			mut.new_pieces.push(new_p);
			self.pieces.push(new_p);

		default:
			BytePos current_offset = 0;
			bool handled = false;
			for (sz i = 0; i < self.pieces.len(); i++)
			{
				Piece p = self.pieces[i];
				if (pos == current_offset)
				{
					mut.piece_index = i;
					mut.old_pieces.init(self.allocator, 0);
					mut.new_pieces.init(self.allocator, 1);
					mut.new_pieces.push(new_p);
					self.pieces.insert_at(i, new_p);
					handled = true;
					break;
				}

				if (pos > current_offset && pos < current_offset + p.length)
				{
					BytePos left_len  = pos - current_offset;
					BytePos right_len = p.length - left_len;

					Piece left_piece  = make_sub_piece(self, p, 0, left_len);
					Piece right_piece = make_sub_piece(self, p, left_len, right_len);

					mut.piece_index = i;
					mut.old_pieces.init(self.allocator, 1);
					mut.old_pieces.push(p);

					mut.new_pieces.init(self.allocator, 3);
					mut.new_pieces.push(left_piece);
					mut.new_pieces.push(new_p);
					mut.new_pieces.push(right_piece);

					self.pieces[i] = left_piece;
					self.pieces.insert_at(i + 1, new_p);
					self.pieces.insert_at(i + 2, right_piece);
					handled = true;
					break;
				}
				current_offset += p.length;
			}
			if (!handled)
			{
				sz idx = self.pieces.len();
				mut.piece_index = idx;
				mut.old_pieces.init(self.allocator, 0);
				mut.new_pieces.init(self.allocator, 1);
				mut.new_pieces.push(new_p);
				self.pieces.push(new_p);
			}
	}

	self.record_mutation(mut);
	self.cached_total_length += byte_len;
}

fn void PieceTable.replace_range(&self, BytePos start, BytePos end, char[] bytes)
{
	if (start == end || start >= self.cached_total_length)
	{
		self.insert_bytes(start, bytes);
		return;
	}

	BytePos s = math::min(start, self.cached_total_length);
	BytePos e = math::min(end, self.cached_total_length);
	if (s >= e)
	{
		self.insert_bytes(s, bytes);
		return;
	}

	PieceSpan span;
	if (!self.find_piece_span(s, e, &span)) return;

	Piece start_p = self.pieces[span.start_idx];
	Piece end_p   = self.pieces[span.end_idx];

	PieceMutation mut;
	mut.piece_index = span.start_idx;

	sz old_count = span.end_idx - span.start_idx + 1;
	mut.old_pieces.init(self.allocator, old_count);
	for (sz i = span.start_idx; i <= span.end_idx; i++)
	{
		mut.old_pieces.push(self.pieces[i]);
	}

	mut.new_pieces.init(self.allocator, 3);

	if (span.start_offset > 0)
	{
		mut.new_pieces.push(make_sub_piece(self, start_p, 0, span.start_offset));
	}

	BytePos byte_len = bytes.len;
	if (byte_len > 0)
	{
		self.ensure_add_capacity(byte_len);
		BytePos add_offset = self.add_len;
		mem::copy(&self.add_buffer[add_offset], bytes.ptr, byte_len);
		self.add_len += byte_len;

		sz lines = count_newlines(bytes);
		mut.new_pieces.push({ .source = ADD, .offset = add_offset, .length = byte_len, .line_count = lines });
	}

	if (span.end_offset < end_p.length)
	{
		mut.new_pieces.push(make_sub_piece(self, end_p, span.end_offset, end_p.length - span.end_offset));
	}

	sz remaining = self.pieces.len() - (span.end_idx + 1);
	if (remaining > 0)
	{
		mem::move(
			&self.pieces.entries[span.start_idx],
			&self.pieces.entries[span.end_idx + 1],
			remaining * Piece::size
		);
	}
	self.pieces.size -= old_count;

	for (sz i = 0; i < mut.new_pieces.len(); i++)
	{
		self.pieces.insert_at(span.start_idx + i, mut.new_pieces[i]);
	}

	self.record_mutation(mut);
	self.cached_total_length = self.cached_total_length - (e - s) + byte_len;
}

fn void PieceTable.delete_range(&self, BytePos start, BytePos end)
{
	self.replace_range(start, end, { });
}

fn void PieceTable.apply_mutation_list(&self, List{PieceMutation}* mutations, bool is_undo)
{
	sz mut_count = mutations.len();
	for (sz step = 0; step < mut_count; step++)
	{
		sz k = is_undo ? (mut_count - 1 - step) : step;
		PieceMutation* mut = &(*mutations)[k];

		List{Piece}* remove_list = is_undo ? &mut.new_pieces : &mut.old_pieces;
		List{Piece}* insert_list = is_undo ? &mut.old_pieces : &mut.new_pieces;

		sz num_remove = remove_list.len();
		sz remaining  = self.pieces.len() - (mut.piece_index + num_remove);
		if (remaining > 0)
		{
			mem::move(
				&self.pieces.entries[mut.piece_index],
				&self.pieces.entries[mut.piece_index + num_remove],
				remaining * Piece::size
			);
		}
		self.pieces.size -= num_remove;

		for (sz i = 0; i < insert_list.len(); i++)
		{
			self.pieces.insert_at(mut.piece_index + i, (*insert_list)[i]);
		}
	}
	self.recalculate_total_length();
}

fn bool PieceTable.undo_with_range(
	&self,
	List{Cursor}* out_cursors,
	BytePos* out_edit_start,
	BytePos* out_deleted_len,
	BytePos* out_inserted_len
)
{
	UndoTransaction*? tx_opt = self.undo_stack.pop();
	if (catch tx_opt) return false;
	UndoTransaction* tx = tx_opt;

	BytePos edit_start = 0;
	BytePos del_len = 0;
	BytePos ins_len = 0;

	if (tx.mutations.len() > 0)
	{
		sz first_p_idx = tx.mutations[0].piece_index;
		BytePos offset = 0;
		for (sz i = 0; i < first_p_idx && i < self.pieces.len(); i++)
		{
			offset += self.pieces[i].length;
		}
		edit_start = offset;

		foreach (&mut : tx.mutations)
		{
			foreach (&p : mut.new_pieces) del_len += p.length;
			foreach (&p : mut.old_pieces) ins_len += p.length;
		}
	}

	self.apply_mutation_list(&tx.mutations, true);

	out_cursors.clear();
	for (sz i = 0; i < tx.cursors_before.len(); i++)
	{
		out_cursors.push(tx.cursors_before[i]);
	}

	self.redo_stack.push(tx);

	*out_edit_start = edit_start;
	*out_deleted_len = del_len;
	*out_inserted_len = ins_len;
	return true;
}

fn bool PieceTable.redo_with_range(
	&self,
	List{Cursor}* out_cursors,
	BytePos* out_edit_start,
	BytePos* out_deleted_len,
	BytePos* out_inserted_len
)
{
	UndoTransaction*? tx_opt = self.redo_stack.pop();
	if (catch tx_opt) return false;
	UndoTransaction* tx = tx_opt;

	BytePos edit_start = 0;
	BytePos del_len = 0;
	BytePos ins_len = 0;

	if (tx.mutations.len() > 0)
	{
		sz first_p_idx = tx.mutations[0].piece_index;
		BytePos offset = 0;
		for (sz i = 0; i < first_p_idx && i < self.pieces.len(); i++)
		{
			offset += self.pieces[i].length;
		}
		edit_start = offset;

		foreach (&mut : tx.mutations)
		{
			foreach (&p : mut.old_pieces) del_len += p.length;
			foreach (&p : mut.new_pieces) ins_len += p.length;
		}
	}

	self.apply_mutation_list(&tx.mutations, false);

	out_cursors.clear();
	for (sz i = 0; i < tx.cursors_after.len(); i++)
	{
		out_cursors.push(tx.cursors_after[i]);
	}

	self.undo_stack.push(tx);

	*out_edit_start = edit_start;
	*out_deleted_len = del_len;
	*out_inserted_len = ins_len;
	return true;
}

fn void PieceTable.append_range_to_dstring(&self, DString* ds, BytePos start, BytePos end)
{
	BytePos s = math::min(start, self.cached_total_length);
	BytePos e = math::min(end, self.cached_total_length);
	if (s >= e) return;

	BytePos current_offset = 0;
	foreach (&p : self.pieces)
	{
		BytePos piece_start = current_offset;
		BytePos piece_end   = current_offset + p.length;

		if (piece_end > s && piece_start < e)
		{
			BytePos sub_start = s > piece_start ? s - piece_start : 0;
			BytePos sub_end   = e < piece_end ? e - piece_start : p.length;
			BytePos len       = sub_end - sub_start;

			char[] slice = (p.source == ORIGINAL)
				? self.original_buffer[p.offset + sub_start:len]
				: self.add_buffer[p.offset + sub_start:len];

			ds.append_bytes(slice);
		}
		current_offset += p.length;
	}
}

fn String PieceTable.get_slice(&self, BytePos start, BytePos end, Allocator allocator = tmem)
{
	BytePos s = math::min(start, self.cached_total_length);
	BytePos e = math::min(end, self.cached_total_length);
	if (s >= e) return "";

	PieceSpan span;
	if (self.find_piece_span(s, e, &span))
	{
		if (span.start_idx == span.end_idx)
		{
			Piece p = self.pieces[span.start_idx];
			BytePos len = e - s;
			char[] slice = (p.source == ORIGINAL)
				? self.original_buffer[p.offset + span.start_offset:len]
				: self.add_buffer[p.offset + span.start_offset:len];
			return (String)slice;
		}
	}

	DString ds;
	ds.init(allocator, (e - s) + 16);
	self.append_range_to_dstring(&ds, s, e);
	return ds.copy_str(allocator);
}

fn String PieceTable.to_string(&self, Allocator allocator = mem)
{
	DString ds;
	ds.init(allocator, self.cached_total_length + 16);
	self.append_range_to_dstring(&ds, 0, self.cached_total_length);
	return ds.copy_str(allocator);
}

fn String PieceTable.to_tstring(&self) => self.to_string(tmem);

fn sz? PieceTable.to_format(&self, Formatter* fmt) @dynamic
{
	sz total = 0;
	foreach (&p : self.pieces)
	{
		char[] slice = (p.source == ORIGINAL)
			? self.original_buffer[p.offset:p.length]
			: self.add_buffer[p.offset:p.length];
		total += fmt.print((String)slice)!;
	}
	return total;
}
