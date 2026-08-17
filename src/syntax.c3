module c3ed::syntax;
import std, c3ed::config;

enum LineState : char
{
	NORMAL,
	IN_BLOCK_COMMENT,
	IN_CONTRACT_COMMENT,
	IN_RAW_STRING
}

enum TokenType : (Color color, String[] keywords)
{
	DEFAULT { { 226, 232, 240, 255 }, { } },

	KEYWORD { { 255, 123, 114, 255 }, {
		"alias", "assert", "asm", "attrdef", "attrgroup", "attrmacro", "bitstruct", "break",
		"case", "catch", "cenum", "const", "constdef", "constset", "continue", "default",
		"defer", "distinct", "do", "else", "enum", "extern", "false", "faultconst", "faultdef",
		"faultset", "fn", "for", "foreach", "foreach_r", "if", "import", "inline", "interface",
		"lengthof", "macro", "module", "nextcase", "null", "return", "scope", "static", "struct",
		"switch", "tlocal", "true", "try", "typedef", "union", "var", "while", "excuse"
	} },

	TYPE { { 126, 231, 135, 255 }, {
		"any", "void", "bool", "char", "double", "float", "float16", "bfloat", "bfloat16",
		"float128", "int128", "int", "ichar", "iptr", "sz", "long", "short", "uint128",
		"uint", "ulong", "uptr", "ushort", "usz", "typeid", "fault", "untypedlist",
		"$Typeof", "$Typefrom"
	} },

	ATTRIBUTE { { 255, 166, 87, 255 }, {
		"@align", "@allow_deprecated", "@benchmark", "@bigendian", "@builtin", "@callconv",
		"@cname", "@compact", "@const", "@constinit", "@deprecated", "@dynamic", "@export",
		"@feat", "@finalizer", "@format", "@if", "@init", "@inline", "@jump", "@link",
		"@littleendian", "@local", "@maydiscard", "@mustinit", "@naked", "@noalias",
		"@nodiscard", "@noinit", "@noinline", "@nopadding", "@norecurse", "@noreturn",
		"@nosanitize", "@nostrip", "@obfuscate", "@operator", "@operator_r", "@operator_s",
		"@optional", "@overlap", "@packed", "@private", "@public", "@pure", "@reflect",
		"@safeinfer", "@safemacro", "@section", "@simd", "@tag", "@test", "@unused",
		"@used", "@wasm", "@weak", "@weaklink", "@winmain"
	} },

	DIRECTIVE { { 255, 123, 114, 255 }, {
		"$assert", "$case", "$concat", "$default", "$defined", "$echo", "$else", "$embed",
		"$endfor", "$endforeach", "$endif", "$endswitch", "$error", "$eval", "$exec", "$expand",
		"$feat", "$feature", "$for", "$foreach", "$if", "$include", "$reflect", "$stringify",
		"$switch", "$vaarg", "$vaexpr", "$varef"
	} },

	BUILTIN { { 210, 168, 255, 255 }, {
		"$$abs", "$$acos", "$$asin", "$$atan", "$$any_make", "$$atomic_load", "$$atomic_store",
		"$$atomic_fetch_exchange", "$$atomic_fetch_add", "$$atomic_fetch_sub", "$$atomic_fetch_and",
		"$$atomic_fetch_nand", "$$atomic_fetch_or", "$$atomic_fetch_xor", "$$atomic_fetch_max",
		"$$atomic_fetch_min", "$$atomic_fetch_inc_wrap", "$$atomic_fetch_dec_wrap", "$$bitreverse",
		"$$breakpoint", "$$bswap", "$$ceil", "$$compare_exchange", "$$copysign", "$$cos", "$$cosh",
		"$$clz", "$$ctz", "$$add", "$$div", "$$mod", "$$mul", "$$neg", "$$sub", "$$exp", "$$exp2",
		"$$exp10", "$$expect", "$$expect_with_probability", "$$fence", "$$floor", "$$fma",
		"$$fmuladd", "$$frameaddress", "$$fshl", "$$fshr", "$$gather", "$$get_rounding_mode",
		"$$int_to_mask", "$$log", "$$log2", "$$log10", "$$matrix_mul", "$$matrix_transpose",
		"$$mask_to_int", "$$masked_load", "$$masked_store", "$$max", "$$memcpy", "$$memcpy_inline",
		"$$memmove", "$$memset", "$$memset_inline", "$$min", "$$nearbyint", "$$overflow_add",
		"$$overflow_mul", "$$overflow_sub", "$$popcount", "$$pow", "$$pow_int", "$$prefetch",
		"$$reduce_add", "$$reduce_and", "$$reduce_fadd", "$$reduce_fmul", "$$reduce_max",
		"$$reduce_min", "$$reduce_mul", "$$reduce_or", "$$reduce_xor", "$$reverse", "$$returnaddress",
		"$$rint", "$$rnd", "$$round", "$$roundeven", "$$sat_add", "$$sat_shl", "$$sat_sub",
		"$$sat_mul", "$$scatter", "$$select", "$$set_rounding_mode", "$$sprintf", "$$str_find",
		"$$str_hash", "$$str_lower", "$$str_pascalcase", "$$str_replace", "$$str_upper",
		"$$str_snakecase", "$$swizzle", "$$swizzle2", "$$sin", "$$sinh", "$$sqrt", "$$syscall",
		"$$sysclock", "$$tan", "$$tanh", "$$trap", "$$trunc", "$$unaligned_load", "$$unaligned_store",
		"$$unreachable", "$$veccomplt", "$$veccomple", "$$veccompgt", "$$veccompge", "$$veccompeq",
		"$$veccompne", "$$volatile_load", "$$volatile_store", "$$wasm_memory_size", "$$wasm_memory_grow",
		"$$wstr16", "$$wstr32", "$$DATE", "$$FILE", "$$FILEPATH", "$$FUNC", "$$FUNCTION", "$$LINE",
		"$$LINE_RAW", "$$MODULE", "$$BENCHMARK_NAMES", "$$BENCHMARK_FNS", "$$TEST_NAMES", "$$TEST_FNS",
		"$$TIME"
	} },

	FUNCTION       { { 210, 168, 255, 255 }, { } },
	NUMBER         { { 121, 192, 255, 255 }, { } },
	STRING_LITERAL { { 165, 214, 255, 255 }, { } },
	COMMENT        { { 139, 148, 158, 255 }, { } },
	CONTRACT       { { 165, 180, 198, 255 }, { } },
	OPERATOR       { { 255, 123, 114, 255 }, { } },
	DELIMITER      { { 201, 209, 217, 255 }, { } }
}

fn TokenType match_word_token(String w, bool is_fn)
{
	if (w.len == 0) return DEFAULT;

	char c0 = w[0];

	if (c0 == '@')
	{
		foreach (aw : TokenType.ATTRIBUTE.keywords)
		{
			if (aw == w) return ATTRIBUTE;
		}
		return DEFAULT;
	}

	if (c0 == '$')
	{
		if (w.len > 1 && w[1] == '$')
		{
			foreach (bw : TokenType.BUILTIN.keywords)
			{
				if (bw == w) return BUILTIN;
			}
		}
		else
		{
			foreach (dw : TokenType.DIRECTIVE.keywords)
			{
				if (dw == w) return DIRECTIVE;
			}
		}
		return DEFAULT;
	}

	foreach (kw : TokenType.KEYWORD.keywords)
	{
		if (kw == w) return KEYWORD;
	}
	foreach (tw : TokenType.TYPE.keywords)
	{
		if (tw == w) return TYPE;
	}

	switch
	{
		case w.len > 1 && (c0 == 'i' || c0 == 'u') && w[1].is_digit():
			return TYPE;
		case c0.is_upper():
			return TYPE;
		case is_fn:
			return FUNCTION;
		default:
			return DEFAULT;
	}
}

fn LineState lex_state_only(String line, LineState initial_state)
{
	LineState state = initial_state;
	sz len          = line.len;
	sz idx          = 0;

	while (idx < len)
	{
		char c = line[idx];
		switch
		{
			case state == IN_BLOCK_COMMENT:
				if (c == '*' && idx + 1 < len && line[idx + 1] == '/')
				{
					state = NORMAL;
					idx++;
				}
				idx++;

			case state == IN_CONTRACT_COMMENT:
				if (c == '*' && idx + 1 < len && line[idx + 1] == '>')
				{
					state = NORMAL;
					idx++;
				}
				idx++;

			case state == IN_RAW_STRING:
				if (c == '`')
				{
					state = NORMAL;
				}
				idx++;

			case (c == '/' && idx + 1 < len && line[idx + 1] == '/') || (c == '#' && idx + 1 < len && line[idx + 1] == '!'):
				return state;

			case c == '/' && idx + 1 < len && line[idx + 1] == '*':
				state = IN_BLOCK_COMMENT;
				idx += 2;

			case c == '<' && idx + 1 < len && line[idx + 1] == '*' && !(idx > 0 && line[idx - 1] == '['):
				state = IN_CONTRACT_COMMENT;
				idx += 2;

			case c == '\\' && idx + 1 < len && line[idx + 1] == '\\':
				return state;

			case c == '`':
				state = IN_RAW_STRING;
				idx++;

			case c == '"' || c == '\'':
				char q = c;
				idx++;
				while (idx < len)
				{
					char sc = line[idx];
					if (sc == '\\' && idx + 1 < len)
					{
						idx += 2;
						continue;
					}
					idx++;
					if (sc == q) break;
				}

			default:
				idx++;
		}
	}
	return state;
}

fn LineState lex_slice(String line, LineState initial_state, TokenType[] out_tokens)
{
	LineState state = initial_state;
	sz len          = line.len;
	sz idx          = 0;

	while (idx < len)
	{
		char c = line[idx];
		switch
		{
			case state == IN_BLOCK_COMMENT:
				out_tokens[idx] = COMMENT;
				if (c == '*' && idx + 1 < len && line[idx + 1] == '/')
				{
					state = NORMAL;
					idx++;
					if (idx < len) out_tokens[idx] = COMMENT;
				}
				idx++;

			case state == IN_CONTRACT_COMMENT:
				out_tokens[idx] = CONTRACT;
				if (c == '*' && idx + 1 < len && line[idx + 1] == '>')
				{
					state = NORMAL;
					idx++;
					if (idx < len) out_tokens[idx] = CONTRACT;
				}
				idx++;

			case state == IN_RAW_STRING:
				out_tokens[idx] = STRING_LITERAL;
				if (c == '`')
				{
					state = NORMAL;
				}
				idx++;

			case (c == '/' && idx + 1 < len && line[idx + 1] == '/') || (c == '#' && idx + 1 < len && line[idx + 1] == '!'):
				while (idx < len)
				{
					out_tokens[idx++] = COMMENT;
				}

			case c == '/' && idx + 1 < len && line[idx + 1] == '*':
				out_tokens[idx++] = COMMENT;
				if (idx < len) out_tokens[idx++] = COMMENT;
				state = IN_BLOCK_COMMENT;

			case c == '<' && idx + 1 < len && line[idx + 1] == '*' && !(idx > 0 && line[idx - 1] == '['):
				out_tokens[idx++] = CONTRACT;
				if (idx < len) out_tokens[idx++] = CONTRACT;
				state = IN_CONTRACT_COMMENT;

			case c == '\\' && idx + 1 < len && line[idx + 1] == '\\':
				while (idx < len)
				{
					out_tokens[idx++] = STRING_LITERAL;
				}

			case c == '`':
				out_tokens[idx++] = STRING_LITERAL;
				state = IN_RAW_STRING;

			case c == '"' || c == '\'':
				char q = c;
				out_tokens[idx++] = STRING_LITERAL;
				while (idx < len)
				{
					char sc = line[idx];
					out_tokens[idx++] = STRING_LITERAL;
					if (sc == '\\' && idx < len)
					{
						out_tokens[idx++] = STRING_LITERAL;
						continue;
					}
					if (sc == q) break;
				}

			case c.is_digit():
				sz n_start = idx;
				while (idx < len && (line[idx].is_alnum() || line[idx] == '.' || line[idx] == '_'))
				{
					idx++;
				}
				for (sz k = n_start; k < idx; k++)
				{
					out_tokens[k] = NUMBER;
				}

			case c.is_alpha() || c == '_' || c == '@' || c == '$' || (c & 0x80) != 0:
				sz id_start = idx;
				while (idx < len && (line[idx].is_alnum() || line[idx] == '_' || line[idx] == '$' || line[idx] == '@' || (line[idx] & 0x80) != 0))
				{
					idx++;
				}
				String word = line[id_start:idx - id_start];

				sz p = idx;
				while (p < len && (line[p] == ' ' || line[p] == '\t')) p++;
				bool is_fn = (p < len && line[p] == '(');

				TokenType t = match_word_token(word, is_fn);
				for (sz k = id_start; k < idx; k++)
				{
					out_tokens[k] = t;
				}

			default:
				switch (c)
				{
					case ';':
					case ',':
					case '.':
					case '{':
					case '}':
					case '(':
					case ')':
					case '[':
					case ']':
						out_tokens[idx++] = DELIMITER;
					default:
						out_tokens[idx++] = OPERATOR;
				}
		}
	}
	return state;
}
